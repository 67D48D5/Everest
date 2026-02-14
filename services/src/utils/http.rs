//! Generic HTTP utilities for fetching JSON, HTML, and downloading files.
//!
//! Provides a reusable [`HttpClient`] with automatic retries, exponential backoff,
//! streaming downloads, and content-length validation.

use std::{path::Path, time::Duration};

use anyhow::{Context, Result, bail};
use log::{debug, warn};
use reqwest::{Client, StatusCode};
use serde::de::DeserializeOwned;
use tokio::{fs::File, io::AsyncWriteExt};

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

/// Configuration for the HTTP client.
#[derive(Debug, Clone)]
pub struct ClientConfig {
    pub user_agent: String,
    pub connect_timeout: Duration,
    pub request_timeout: Duration,
    pub initial_retry_delay: Duration,
    pub max_retries: u32,
}

impl Default for ClientConfig {
    fn default() -> Self {
        Self {
            user_agent: "Everest/3.0.0 (https://github.com/E414CF6/Everest)".into(),
            connect_timeout: Duration::from_secs(5),
            request_timeout: Duration::from_secs(120),
            initial_retry_delay: Duration::from_secs(1),
            max_retries: 3,
        }
    }
}

// ---------------------------------------------------------------------------
// Client
// ---------------------------------------------------------------------------

/// Reusable HTTP client with retry logic and exponential backoff.
#[derive(Clone)]
pub struct HttpClient {
    client: Client,
    config: ClientConfig,
}

impl HttpClient {
    /// Creates a client with default configuration.
    pub fn new() -> Result<Self> {
        Self::with_config(ClientConfig::default())
    }

    /// Creates a client with custom configuration.
    pub fn with_config(config: ClientConfig) -> Result<Self> {
        let client = Client::builder()
            .user_agent(&config.user_agent)
            .connect_timeout(config.connect_timeout)
            .timeout(config.request_timeout)
            .build()
            .context("Failed to build HTTP client")?;

        Ok(Self { client, config })
    }

    // -----------------------------------------------------------------------
    // Retry engine
    // -----------------------------------------------------------------------

    /// Executes a request with automatic retries and exponential backoff.
    ///
    /// Only retries on:
    /// - Server errors (5xx)
    /// - Rate limiting (429)
    /// - Connection / timeout errors
    ///
    /// Client errors (4xx except 429) are returned immediately without retry.
    async fn execute_with_retry<F>(&self, url: &str, build_request: F) -> Result<reqwest::Response>
    where
        F: Fn() -> reqwest::RequestBuilder,
    {
        let mut last_err = None;

        for attempt in 0..=self.config.max_retries {
            if attempt > 0 {
                let delay = self.config.initial_retry_delay * 2u32.pow(attempt - 1);
                warn!(
                    "Retry {attempt}/{} for {url} (backoff {delay:?})",
                    self.config.max_retries
                );
                tokio::time::sleep(delay).await;
            }

            match build_request().send().await {
                Ok(resp) => {
                    let status = resp.status();

                    if status.is_success() {
                        return Ok(resp);
                    }

                    // Retryable server-side errors
                    if status.is_server_error() || status == StatusCode::TOO_MANY_REQUESTS {
                        last_err = Some(anyhow::anyhow!("HTTP {status} from {url}"));
                        continue;
                    }

                    // Non-retryable client errors (400, 401, 403, 404, …)
                    bail!("HTTP {status} from {url}");
                }
                Err(e) if e.is_timeout() || e.is_connect() => {
                    last_err = Some(anyhow::anyhow!("Connection error for {url}: {e}"));
                }
                Err(e) => {
                    // Non-retryable request error (e.g. invalid URL, redirect loop)
                    bail!("Request failed for {url}: {e}");
                }
            }
        }

        Err(last_err.unwrap_or_else(|| anyhow::anyhow!("Max retries exceeded for {url}")))
    }

    // -----------------------------------------------------------------------
    // Public API
    // -----------------------------------------------------------------------

    /// Fetches and deserializes JSON from a URL.
    pub async fn fetch_json<T: DeserializeOwned>(&self, url: &str) -> Result<T> {
        let resp = self
            .execute_with_retry(url, || {
                self.client.get(url).header("Accept", "application/json")
            })
            .await
            .with_context(|| format!("Failed to fetch JSON from {url}"))?;

        resp.json::<T>()
            .await
            .with_context(|| format!("Failed to parse JSON from {url}"))
    }

    /// Fetches a URL and returns the response body as a string.
    pub async fn fetch_html(&self, url: &str) -> Result<String> {
        let resp = self
            .execute_with_retry(url, || self.client.get(url))
            .await
            .with_context(|| format!("Failed to fetch HTML from {url}"))?;

        resp.text()
            .await
            .with_context(|| format!("Failed to read body from {url}"))
    }

    /// Downloads a file via streaming chunks to a temporary path, then atomically renames it.
    ///
    /// If the server provided a `Content-Length` header the downloaded size is validated
    /// after streaming completes — a mismatch removes the temp file and returns an error.
    pub async fn download_file(&self, url: &str, dest: &Path) -> Result<()> {
        let resp = self
            .execute_with_retry(url, || self.client.get(url))
            .await
            .with_context(|| format!("Failed to start download from {url}"))?;

        let content_length = resp.content_length();

        // Write to a temp file first so a failed download never leaves a partial artifact.
        let tmp_path = dest.with_extension(format!("tmp.{}", std::process::id()));
        let mut file = File::create(&tmp_path)
            .await
            .with_context(|| format!("Failed to create temp file: {}", tmp_path.display()))?;

        let mut downloaded: u64 = 0;
        let mut resp = resp;

        // Stream download via chunk() — no extra feature flags required.
        while let Some(chunk) = resp
            .chunk()
            .await
            .context("Error reading download stream")?
        {
            file.write_all(&chunk)
                .await
                .context("Error writing to temp file")?;
            downloaded += chunk.len() as u64;
        }

        // Validate against Content-Length when available.
        if let Some(expected) = content_length {
            if downloaded != expected {
                let _ = tokio::fs::remove_file(&tmp_path).await;
                bail!("Size mismatch for {url}: expected {expected} bytes, got {downloaded}");
            }
        }

        debug!("Downloaded {downloaded} bytes from {url}");

        // Flush → sync → close → rename (atomic on the same filesystem).
        file.flush().await.context("Failed to flush file buffer")?;
        file.sync_all().await.context("Failed to sync file data")?;
        drop(file);

        tokio::fs::rename(&tmp_path, dest).await.with_context(|| {
            format!(
                "Failed to rename {} → {}",
                tmp_path.display(),
                dest.display()
            )
        })?;

        Ok(())
    }
}
