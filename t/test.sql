DROP TABLE IF EXISTS test;
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
