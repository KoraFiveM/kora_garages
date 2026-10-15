CREATE TABLE IF NOT EXISTS `qbgarages_property_garages` (
  `id` VARCHAR(50) NOT NULL,
  `provider` VARCHAR(64) NOT NULL,
  `definition` LONGTEXT NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
