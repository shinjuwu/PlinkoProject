/*
 Navicat Premium Data Transfer

 Source Server         : DEV
 Source Server Type    : PostgreSQL
 Source Server Version : 140010 (140010)
 Source Host           : 172.30.0.154:5432
 Source Catalog        : dayon
 Source Schema         : public

 Target Server Type    : PostgreSQL
 Target Server Version : 140010 (140010)
 File Encoding         : 65001

 Date: 02/04/2024 09:27:40
*/


-- ----------------------------
-- Table structure for gamelist
-- ----------------------------
DROP TABLE IF EXISTS "public"."gamelist";
CREATE TABLE "public"."gamelist" (
  "game_id" int4 NOT NULL DEFAULT 0,
  "game_code" varchar(50) COLLATE "pg_catalog"."default",
  "status" int4 NOT NULL DEFAULT 0
)
;

-- ----------------------------
-- Records of gamelist
-- ----------------------------
INSERT INTO "public"."gamelist" VALUES (3001, 'fruitslot', 1);
INSERT INTO "public"."gamelist" VALUES (3002, 'rcfishing', 1);
INSERT INTO "public"."gamelist" VALUES (3003, 'plinko', 1);
INSERT INTO "public"."gamelist" VALUES (4001, 'fruit777slot', 1);
INSERT INTO "public"."gamelist" VALUES (1001, 'baccarat', 1);
INSERT INTO "public"."gamelist" VALUES (0, '', 0);
INSERT INTO "public"."gamelist" VALUES (2010, 'okey', 1);
INSERT INTO "public"."gamelist" VALUES (4003, 'midasslot', 1);
INSERT INTO "public"."gamelist" VALUES (1010, 'roulette', 1);
INSERT INTO "public"."gamelist" VALUES (4002, 'megsharkslot', 1);
INSERT INTO "public"."gamelist" VALUES (2002, 'sangong', 1);
INSERT INTO "public"."gamelist" VALUES (2011, 'teenpatti', 1);
INSERT INTO "public"."gamelist" VALUES (1002, 'fantan', 1);
INSERT INTO "public"."gamelist" VALUES (1003, 'colordisc', 1);
INSERT INTO "public"."gamelist" VALUES (1004, 'prawncrab', 1);
INSERT INTO "public"."gamelist" VALUES (1005, 'hundredsicbo', 1);
INSERT INTO "public"."gamelist" VALUES (1006, 'cockfight', 1);
INSERT INTO "public"."gamelist" VALUES (1007, 'dogracing', 1);
INSERT INTO "public"."gamelist" VALUES (1008, 'rocket', 1);
INSERT INTO "public"."gamelist" VALUES (1009, 'andarbahar', 1);
INSERT INTO "public"."gamelist" VALUES (2001, 'blackjack', 1);
INSERT INTO "public"."gamelist" VALUES (2003, 'bullbull', 1);
INSERT INTO "public"."gamelist" VALUES (2004, 'texas', 1);
INSERT INTO "public"."gamelist" VALUES (9001, 'jackpot', 1);
INSERT INTO "public"."gamelist" VALUES (2005, 'rummy', 1);
INSERT INTO "public"."gamelist" VALUES (2006, 'goldenflower', 1);
INSERT INTO "public"."gamelist" VALUES (2007, 'pokdeng', 1);
INSERT INTO "public"."gamelist" VALUES (2008, 'catte', 1);
INSERT INTO "public"."gamelist" VALUES (2009, 'chinesepoker', 1);
INSERT INTO "public"."gamelist" VALUES (3004, 'happyfishing', 1);
INSERT INTO "public"."gamelist" VALUES (4004, 'wildgemslot', 1);
INSERT INTO "public"."gamelist" VALUES (4005, 'jumphighslot', 1);
INSERT INTO "public"."gamelist" VALUES (4006, 'pyrtreasureslot', 1);

-- ----------------------------
-- Primary Key structure for table gamelist
-- ----------------------------
ALTER TABLE "public"."gamelist" ADD CONSTRAINT "gamelist_pkey" PRIMARY KEY ("game_id");
