//! Generic HTTP utilities for fetching JSON, HTML, and downloading files with retries and timeouts.

use std::{path::Path, time::Duration};

use anyhow::{Context, Result, bail};
use reqwest::{Client, StatusCode};
use serde::de::DeserializeOwned;
use tokio::{fs::File, io::AsyncWriteExt};

// Structure for HTTP client configuration, allowing customization of user agent, timeouts, retry behavior, etc.
#[derive(Debug, Clone)]
pub struct ClientConfig {
    pub user_agent: String,
    pub connect_timeout: Duration,
    pub request_timeout: Duration,
    pub retry_delay: Duration,
    pub max_retries: u32,
}

impl Default for ClientConfig {
    fn default() -> Self {
        Self {
            user_agent: "Everest/3.0.0 (https://github.com/E414CF6/Everest)".into(),
            connect_timeout: Duration::from_secs(4),
            request_timeout: Duration::from_secs(60),
            retry_delay: Duration::from_secs(2),
            max_retries: 3, // 기본 재시도 횟수 증가
        }
    }
}

#[derive(Clone)]
pub struct HttpClient {
    client: Client,
    config: ClientConfig,
}

impl HttpClient {
    /// 기본 설정으로 클라이언트 생성
    pub fn new() -> Result<Self> {
        Self::with_config(ClientConfig::default())
    }

    /// 사용자 정의 설정으로 클라이언트 생성
    pub fn with_config(config: ClientConfig) -> Result<Self> {
        let client = Client::builder()
            .user_agent(&config.user_agent)
            .connect_timeout(config.connect_timeout)
            .timeout(config.request_timeout)
            .build()
            .context("Failed to build HTTP client")?;

        Ok(Self { client, config })
    }

    /// 내부용: 재시도 로직이 포함된 요청 실행기
    /// `request_builder_fn`: 매 시도마다 새로운 RequestBuilder를 생성하는 클로저
    async fn execute_with_retry<F, Fut>(&self, request_maker: F) -> Result<reqwest::Response>
    where
        F: Fn() -> Fut,
        Fut: std::future::Future<Output = Result<reqwest::RequestBuilder, reqwest::Error>>,
    {
        let mut last_err = None;

        for attempt in 0..=self.config.max_retries {
            if attempt > 0 {
                // 지수 백오프(Exponential Backoff) 적용 가능 (여기선 단순 고정 딜레이)
                tokio::time::sleep(self.config.retry_delay).await;
            }

            // 매 시도마다 RequestBuilder를 새로 생성 (RequestBuilder는 1회용)
            let builder = match request_maker().await {
                Ok(b) => b,
                Err(e) => {
                    last_err = Some(anyhow::anyhow!("Failed to build request: {}", e));
                    continue;
                }
            };

            match builder.send().await {
                Ok(resp) => {
                    let status = resp.status();
                    if status.is_success() {
                        return Ok(resp);
                    } else if status.is_server_error() || status == StatusCode::TOO_MANY_REQUESTS {
                        // 5xx 에러나 429(Rate Limit)일 때만 재시도
                        last_err = Some(anyhow::anyhow!("HTTP Server Error: {}", status));
                        continue;
                    } else {
                        // 404 등 클라이언트 에러는 재시도하지 않고 바로 실패 처리
                        bail!("HTTP Request failed with status: {}", status);
                    }
                }
                Err(e) => {
                    last_err = Some(anyhow::anyhow!("Connection failed: {}", e));
                }
            }
        }

        Err(last_err.unwrap_or_else(|| anyhow::anyhow!("Max retries exceeded")))
    }

    /// JSON 데이터 가져오기 (Generic 적용)
    pub async fn fetch_json<T: DeserializeOwned>(&self, url: &str) -> Result<T> {
        let url = url.to_string(); // 클로저로 이동시키기 위해 소유권 복제
        let resp = self
            .execute_with_retry(|| async {
                Ok(self.client.get(&url).header("Accept", "application/json"))
            })
            .await
            .with_context(|| format!("Failed to fetch JSON from {url}"))?;

        let data = resp
            .json::<T>()
            .await
            .with_context(|| format!("Failed to parse JSON body from {url}"))?;

        Ok(data)
    }

    /// HTML 문자열 가져오기
    pub async fn fetch_html(&self, url: &str) -> Result<String> {
        let url = url.to_string();
        let resp = self
            .execute_with_retry(|| async { Ok(self.client.get(&url)) })
            .await
            .with_context(|| format!("Failed to fetch HTML from {url}"))?;

        let text = resp
            .text()
            .await
            .with_context(|| format!("Failed to read text body from {url}"))?;

        Ok(text)
    }

    /// 파일 다운로드 (Streaming 방식 적용 - 메모리 효율적)
    pub async fn download_file(&self, url: &str, dest: &Path) -> Result<()> {
        let url = url.to_string();

        // 1. 응답 헤더만 먼저 받아옴
        let resp = self
            .execute_with_retry(|| async { Ok(self.client.get(&url)) })
            .await
            .with_context(|| format!("Failed to initiate download from {url}"))?;

        // 2. 임시 파일 생성
        let tmp_path = dest.with_extension(format!("tmp.{}", std::process::id()));
        let mut file = File::create(&tmp_path)
            .await
            .with_context(|| format!("Failed to create temp file: {}", tmp_path.display()))?;

        // 3. 스트리밍으로 파일 쓰기 (Chunk 단위)
        let mut stream = resp.bytes_stream();

        while let Some(chunk_result) = stream.next().await {
            let chunk = chunk_result.context("Error while reading download stream")?;
            file.write_all(&chunk)
                .await
                .context("Error while writing to temp file")?;
        }

        // 버퍼 플러시
        file.flush().await.context("Failed to flush file buffer")?;
        // 파일 핸들을 닫기 위해 스코프 종료 또는 drop이 필요하지만,
        // rename 전에 명시적으로 sync_all을 호출하는 것이 안전함
        file.sync_all().await.context("Failed to sync file data")?;
        drop(file); // 파일 락 해제

        // 4. 파일 이름 변경 (Atomic)
        tokio::fs::rename(&tmp_path, dest).await.with_context(|| {
            format!(
                "Failed to rename {} to {}",
                tmp_path.display(),
                dest.display()
            )
        })?;

        Ok(())
    }
}
