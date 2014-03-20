-- vim:nospell:
DROP TABLE IF EXISTS test;
DROP TABLE IF EXISTS test2p;
DROP TABLE IF EXISTS testnp;
CREATE TABLE test (
    id          integer NOT NULL,
    value2      text,
    valueX      text,
    data_basis  varchar NOT NULL,
    data        blob,
    --
    PRIMARY KEY (id)
);
INSERT INTO test VALUES(1,NULL,NULL,'Test','{"value":"one"}');

CREATE TABLE test2p (
    key1        integer NOT NULL,
    key2        integer NOT NULL,
    val1        text,
    data_basis  varchar NOT NULL,
    data        blob,
    --
    PRIMARY KEY (key1,key2)
);
CREATE TABLE testnp (
    val1        text,
    data_basis  varchar NOT NULL,
    data        blob
);
