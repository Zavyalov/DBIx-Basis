DROP TABLE IF EXISTS test;
CREATE TABLE test (
    id          integer NOT NULL,
    data_basis  varchar NOT NULL,
    data        blob,
    --
    PRIMARY KEY (id)
);
INSERT INTO test VALUES(1,'Test','{"value":"one"}');
