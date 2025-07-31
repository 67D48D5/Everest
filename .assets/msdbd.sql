# ************************************************************
# Sequel Ace SQL dump
# Version 20095
#
# https://sequel-ace.com/
# https://github.com/Sequel-Ace/Sequel-Ace
#
# Database: msdbd
# Host: MySQL 11.8.2-MariaDB
# ************************************************************

USE msdbd;

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
SET NAMES utf8mb4;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE='NO_AUTO_VALUE_ON_ZERO', SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;


# Dump of table cluster
# ------------------------------------------------------------

DROP TABLE IF EXISTS `cluster`;

CREATE TABLE `cluster` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `pos1_x` int(11) NOT NULL,
  `pos1_z` int(11) NOT NULL,
  `pos2_x` int(11) NOT NULL,
  `pos2_z` int(11) NOT NULL,
  `owner` varchar(40) NOT NULL,
  `world` varchar(45) NOT NULL,
  `timestamp` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_uca1400_ai_ci;



# Dump of table cluster_helpers
# ------------------------------------------------------------

DROP TABLE IF EXISTS `cluster_helpers`;

CREATE TABLE `cluster_helpers` (
  `cluster_id` int(11) NOT NULL,
  `user_uuid` varchar(40) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_uca1400_ai_ci;



# Dump of table cluster_invited
# ------------------------------------------------------------

DROP TABLE IF EXISTS `cluster_invited`;

CREATE TABLE `cluster_invited` (
  `cluster_id` int(11) NOT NULL,
  `user_uuid` varchar(40) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_uca1400_ai_ci;



# Dump of table cluster_settings
# ------------------------------------------------------------

DROP TABLE IF EXISTS `cluster_settings`;

CREATE TABLE `cluster_settings` (
  `cluster_id` int(11) NOT NULL,
  `biome` varchar(45) DEFAULT 'FOREST',
  `rain` int(1) DEFAULT 0,
  `custom_time` tinyint(1) DEFAULT 0,
  `time` int(11) DEFAULT 8000,
  `deny_entry` tinyint(1) DEFAULT 0,
  `alias` varchar(50) DEFAULT NULL,
  `merged` int(11) DEFAULT NULL,
  `position` varchar(50) NOT NULL DEFAULT 'DEFAULT',
  PRIMARY KEY (`cluster_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_uca1400_ai_ci;



# Dump of table plot
# ------------------------------------------------------------

DROP TABLE IF EXISTS `plot`;

CREATE TABLE `plot` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `plot_id_x` int(11) NOT NULL,
  `plot_id_z` int(11) NOT NULL,
  `owner` varchar(40) NOT NULL,
  `world` varchar(45) NOT NULL,
  `timestamp` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_uca1400_ai_ci;



# Dump of table plot_comments
# ------------------------------------------------------------

DROP TABLE IF EXISTS `plot_comments`;

CREATE TABLE `plot_comments` (
  `world` varchar(40) NOT NULL,
  `hashcode` int(11) NOT NULL,
  `comment` varchar(40) NOT NULL,
  `inbox` varchar(40) NOT NULL,
  `timestamp` int(11) NOT NULL,
  `sender` varchar(40) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_uca1400_ai_ci;



# Dump of table plot_denied
# ------------------------------------------------------------

DROP TABLE IF EXISTS `plot_denied`;

CREATE TABLE `plot_denied` (
  `plot_plot_id` int(11) NOT NULL,
  `user_uuid` varchar(40) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_uca1400_ai_ci;



# Dump of table plot_flags
# ------------------------------------------------------------

DROP TABLE IF EXISTS `plot_flags`;

CREATE TABLE `plot_flags` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `plot_id` int(11) NOT NULL,
  `flag` varchar(64) DEFAULT NULL,
  `value` varchar(512) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `plot_id` (`plot_id`,`flag`),
  CONSTRAINT `plot_flags_ibfk_1` FOREIGN KEY (`plot_id`) REFERENCES `plot` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_uca1400_ai_ci;



# Dump of table plot_helpers
# ------------------------------------------------------------

DROP TABLE IF EXISTS `plot_helpers`;

CREATE TABLE `plot_helpers` (
  `plot_plot_id` int(11) NOT NULL,
  `user_uuid` varchar(40) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_uca1400_ai_ci;



# Dump of table plot_rating
# ------------------------------------------------------------

DROP TABLE IF EXISTS `plot_rating`;

CREATE TABLE `plot_rating` (
  `plot_plot_id` int(11) NOT NULL,
  `rating` int(2) NOT NULL,
  `player` varchar(40) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_uca1400_ai_ci;



# Dump of table plot_settings
# ------------------------------------------------------------

DROP TABLE IF EXISTS `plot_settings`;

CREATE TABLE `plot_settings` (
  `plot_plot_id` int(11) NOT NULL,
  `biome` varchar(45) DEFAULT 'FOREST',
  `rain` int(1) DEFAULT 0,
  `custom_time` tinyint(1) DEFAULT 0,
  `time` int(11) DEFAULT 8000,
  `deny_entry` tinyint(1) DEFAULT 0,
  `alias` varchar(50) DEFAULT NULL,
  `merged` int(11) DEFAULT NULL,
  `position` varchar(50) NOT NULL DEFAULT 'DEFAULT',
  PRIMARY KEY (`plot_plot_id`),
  CONSTRAINT `plot_settings_ibfk_1` FOREIGN KEY (`plot_plot_id`) REFERENCES `plot` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_uca1400_ai_ci;



# Dump of table plot_trusted
# ------------------------------------------------------------

DROP TABLE IF EXISTS `plot_trusted`;

CREATE TABLE `plot_trusted` (
  `plot_plot_id` int(11) NOT NULL,
  `user_uuid` varchar(40) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_uca1400_ai_ci;




/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;
/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
