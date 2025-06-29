# ************************************************************
# Sequel Ace SQL dump
# Version 20094
#
# https://sequel-ace.com/
# https://github.com/Sequel-Ace/Sequel-Ace
#
# Database: msdwc
# ************************************************************


/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
SET NAMES utf8mb4;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE='NO_AUTO_VALUE_ON_ZERO', SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;


# Dump of table coreprotect_version
# ------------------------------------------------------------

DROP TABLE IF EXISTS `coreprotect_version`;

CREATE TABLE `coreprotect_version` (
  `rowid` int(11) NOT NULL AUTO_INCREMENT,
  `time` int(11) DEFAULT NULL,
  `version` varchar(16) DEFAULT NULL,
  PRIMARY KEY (`rowid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

LOCK TABLES `coreprotect_version` WRITE;
/*!40000 ALTER TABLE `coreprotect_version` DISABLE KEYS */;

INSERT INTO `coreprotect_version` (`rowid`, `time`, `version`)
VALUES
	(1,1748142844,'2.22.4');

/*!40000 ALTER TABLE `coreprotect_version` ENABLE KEYS */;
UNLOCK TABLES;


# Dump of table coreprotect_world
# ------------------------------------------------------------

DROP TABLE IF EXISTS `coreprotect_world`;

CREATE TABLE `coreprotect_world` (
  `rowid` int(11) NOT NULL AUTO_INCREMENT,
  `id` int(11) DEFAULT NULL,
  `world` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`rowid`),
  KEY `id` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

LOCK TABLES `coreprotect_world` WRITE;
/*!40000 ALTER TABLE `coreprotect_world` DISABLE KEYS */;

INSERT INTO `coreprotect_world` (`rowid`, `id`, `world`)
VALUES
	(1,1,'world'),
	(2,2,'world_nether'),
	(3,3,'world_the_end');

/*!40000 ALTER TABLE `coreprotect_world` ENABLE KEYS */;
UNLOCK TABLES;


# Dump of table griefprevention_nextclaimid
# ------------------------------------------------------------

DROP TABLE IF EXISTS `griefprevention_nextclaimid`;

CREATE TABLE `griefprevention_nextclaimid` (
  `nextid` int(11) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

LOCK TABLES `griefprevention_nextclaimid` WRITE;
/*!40000 ALTER TABLE `griefprevention_nextclaimid` DISABLE KEYS */;

INSERT INTO `griefprevention_nextclaimid` (`nextid`)
VALUES
	(30);

/*!40000 ALTER TABLE `griefprevention_nextclaimid` ENABLE KEYS */;
UNLOCK TABLES;


# Dump of table griefprevention_schemaversion
# ------------------------------------------------------------

DROP TABLE IF EXISTS `griefprevention_schemaversion`;

CREATE TABLE `griefprevention_schemaversion` (
  `version` int(11) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

LOCK TABLES `griefprevention_schemaversion` WRITE;
/*!40000 ALTER TABLE `griefprevention_schemaversion` DISABLE KEYS */;

INSERT INTO `griefprevention_schemaversion` (`version`)
VALUES
	(3);

/*!40000 ALTER TABLE `griefprevention_schemaversion` ENABLE KEYS */;
UNLOCK TABLES;


# Dump of table tab_groups
# ------------------------------------------------------------

DROP TABLE IF EXISTS `tab_groups`;

CREATE TABLE `tab_groups` (
  `group` varchar(64) DEFAULT NULL,
  `property` varchar(16) DEFAULT NULL,
  `value` varchar(1024) DEFAULT NULL,
  `world` varchar(64) DEFAULT NULL,
  `server` varchar(64) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

LOCK TABLES `tab_groups` WRITE;
/*!40000 ALTER TABLE `tab_groups` DISABLE KEYS */;

INSERT INTO `tab_groups` (`group`, `property`, `value`, `world`, `server`)
VALUES
	('_DEFAULT_','tabprefix','%luckperms-prefix%',NULL,NULL),
	('_DEFAULT_','tagprefix','%luckperms-prefix%',NULL,NULL),
	('_DEFAULT_','customtabname','%displayname%',NULL,NULL),
	('_DEFAULT_','tabsuffix','%luckperms-suffix%',NULL,NULL),
	('_DEFAULT_','tagsuffix','%luckperms-suffix%',NULL,NULL);

/*!40000 ALTER TABLE `tab_groups` ENABLE KEYS */;
UNLOCK TABLES;



/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;
/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
