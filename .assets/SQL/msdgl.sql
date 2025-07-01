# ************************************************************
# Sequel Ace SQL dump
# Version 20094
#
# https://sequel-ace.com/
# https://github.com/Sequel-Ace/Sequel-Ace
#
# Database: msdgl
# ************************************************************


/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
SET NAMES utf8mb4;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE='NO_AUTO_VALUE_ON_ZERO', SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;


# Dump of table luckperms_group_permissions
# ------------------------------------------------------------

DROP TABLE IF EXISTS `luckperms_group_permissions`;

CREATE TABLE `luckperms_group_permissions` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `name` varchar(36) NOT NULL,
  `permission` varchar(200) NOT NULL,
  `value` tinyint(1) NOT NULL,
  `server` varchar(36) NOT NULL,
  `world` varchar(64) NOT NULL,
  `expiry` bigint(20) NOT NULL,
  `contexts` varchar(200) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `luckperms_group_permissions_name` (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

LOCK TABLES `luckperms_group_permissions` WRITE;
/*!40000 ALTER TABLE `luckperms_group_permissions` DISABLE KEYS */;

INSERT INTO `luckperms_group_permissions` (`id`, `name`, `permission`, `value`, `server`, `world`, `expiry`, `contexts`)
VALUES
	(1,'default','coreprotect.inspect',1,'global','global',0,'{}'),
	(2,'default','weight.10',1,'global','global',0,'{}'),
	(4,'admin','weight.20',1,'global','global',0,'{}'),
	(5,'admin','displayname.Admin',1,'global','global',0,'{}'),
	(7,'default','cmi.command.sit',1,'global','global',0,'{}'),
	(8,'default','cmi.command.back',1,'global','global',0,'{}'),
	(9,'default','cmi.command.tpahere',1,'global','global',0,'{}'),
	(10,'default','cmi.command.sethome',1,'global','global',0,'{}'),
	(11,'default','cmi.command.tpaccept',1,'global','global',0,'{}'),
	(12,'default','cmi.command.tpa',1,'global','global',0,'{}'),
	(22,'default','cmi.command.home',1,'global','global',0,'{}'),
	(23,'default','cmi.command.homes',1,'global','global',0,'{}'),
	(28,'default','cmi.command.sethome.unlimited',1,'global','global',0,'{}'),
	(29,'default','cmi.command.sethome.overwrite',1,'global','global',0,'{}'),
	(31,'default','cmi.command.baltop',1,'global','global',0,'{}'),
	(33,'default','cmi.bedhome',1,'global','global',0,'{}'),
	(36,'default','cmi.command.warp.showlist',1,'global','global',0,'{}'),
	(37,'default','cmi.command.nick.different',1,'global','global',0,'{}'),
	(38,'default','cmi.keepinventory',1,'global','global',0,'{}'),
	(40,'default','cmi.command.playtimetop',1,'global','global',0,'{}'),
	(41,'default','cmi.command.warp',1,'global','global',0,'{}'),
	(43,'default','cmi.deathlocation',1,'global','global',0,'{}'),
	(60,'default','mcmmo.defaults',1,'global','global',0,'{}'),
	(61,'default','cmi.command.chatcolor',1,'global','global',0,'{}'),
	(62,'default','cmi.command.spawn',1,'global','global',0,'{}'),
	(63,'default','cmi.command.dback',1,'global','global',0,'{}'),
	(65,'default','cmi.command.nick',1,'global','global',0,'{}'),
	(66,'default','cmi.command.balance',1,'global','global',0,'{}'),
	(67,'default','cmi.command.hat',1,'global','global',0,'{}'),
	(68,'default','cmi.command.removehome',1,'global','global',0,'{}'),
	(69,'default','cmi.command.glow',1,'global','global',0,'{}'),
	(71,'default','cmi.command.glow.color.*',1,'global','global',0,'{}'),
	(72,'default','cmi.command.nick.bypass.length',1,'global','global',0,'{}'),
	(74,'default','cmi.command.nick.bypassblacklist',1,'global','global',0,'{}'),
	(75,'default','cmi.colors.*',1,'global','global',0,'{}'),
	(79,'default','cmi.command.sell',1,'global','global',0,'{}'),
	(80,'default','cmi.command.sell.all',1,'global','global',0,'{}'),
	(81,'default','cmi.command.worth',1,'global','global',0,'{}'),
	(82,'default','cmi.command.worthlist',1,'global','global',0,'{}'),
	(85,'default','cmi.keepexp',1,'global','global',0,'{}'),
	(86,'default','cmi.informdurability',1,'global','global',0,'{}'),
	(88,'default','cmi.command.pay',1,'global','global',0,'{}'),
	(89,'default','cmi.command.reply',1,'global','global',0,'{}'),
	(90,'default','cmi.command.msg',1,'global','global',0,'{}'),
	(91,'default','cmi.command.cheque.withdraw',1,'global','global',0,'{}'),
	(92,'default','cmi.command.helpop',1,'global','global',0,'{}'),
	(93,'default','cmi.command.cheque',1,'global','global',0,'{}'),
	(94,'default','cmi.command.donate',1,'global','global',0,'{}'),
	(95,'default','cmi.command.kit',1,'global','global',0,'{}'),
	(110,'default','griefprevention.transferclaim',1,'global','global',0,'{}'),
	(111,'default','griefprevention.seeinactivity',1,'global','global',0,'{}'),
	(112,'default','griefprevention.buysellclaimblocks',1,'global','global',0,'{}'),
	(113,'default','griefprevention.visualizenearbyclaims',1,'global','global',0,'{}'),
	(114,'default','griefprevention.claims',1,'global','global',0,'{}'),
	(115,'default','griefprevention.trapped',1,'global','global',0,'{}'),
	(116,'default','griefprevention.seeclaimsize',1,'global','global',0,'{}'),
	(117,'default','griefprevention.createclaims',1,'global','global',0,'{}'),
	(125,'default','cmi.elytra.superboost',1,'global','global',0,'{}'),
	(126,'default','cmi.elytra.boost',1,'global','global',0,'{}'),
	(127,'default','cmi.elytra',1,'global','global',0,'{}'),
	(128,'default','cmi.elytra.freeflight',1,'global','global',0,'{}'),
	(129,'default','cmi.elytra.speedometer',1,'global','global',0,'{}'),
	(132,'default','cmi.command.prewards',1,'global','global',0,'{}'),
	(162,'default','cmi.kit.Newbie',1,'global','global',0,'{}'),
	(164,'default','cmi.command.sit.stairs',1,'global','global',0,'{}'),
	(165,'default','cmi.prewards.notification',1,'global','global',0,'{}'),
	(166,'default','cmi.prewards.*',1,'global','global',0,'{}'),
	(167,'admin','prefix.100.&cA &8∥ &c',1,'global','global',0,'{}'),
	(168,'default','prefix.10.&6U &8∥ &6',1,'global','global',0,'{}'),
	(169,'default','displayname.User',1,'global','global',0,'{}'),
	(170,'default','fawe.plotsquared',1,'global','global',0,'{}'),
	(171,'default','plots.permpack.basicflags',1,'global','global',0,'{}'),
	(172,'default','plots.permpack.basicinbox',1,'global','global',0,'{}'),
	(173,'default','plots.permpack.basic',1,'global','global',0,'{}'),
	(174,'default','plots.plot.24',1,'global','global',0,'{}');

/*!40000 ALTER TABLE `luckperms_group_permissions` ENABLE KEYS */;
UNLOCK TABLES;


# Dump of table luckperms_groups
# ------------------------------------------------------------

DROP TABLE IF EXISTS `luckperms_groups`;

CREATE TABLE `luckperms_groups` (
  `name` varchar(36) NOT NULL,
  PRIMARY KEY (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;

LOCK TABLES `luckperms_groups` WRITE;
/*!40000 ALTER TABLE `luckperms_groups` DISABLE KEYS */;

INSERT INTO `luckperms_groups` (`name`)
VALUES
	('admin'),
	('default');

/*!40000 ALTER TABLE `luckperms_groups` ENABLE KEYS */;
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


# Dump of table tab_users
# ------------------------------------------------------------

DROP TABLE IF EXISTS `tab_users`;

CREATE TABLE `tab_users` (
  `user` varchar(64) DEFAULT NULL,
  `property` varchar(16) DEFAULT NULL,
  `value` varchar(1024) DEFAULT NULL,
  `world` varchar(64) DEFAULT NULL,
  `server` varchar(64) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;




/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;
/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
