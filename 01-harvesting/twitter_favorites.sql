DROP TABLE IF EXISTS twitter_favorites  ;
CREATE TABLE twitter_favorites (
    id                  int( 64 ) UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY ,
    consumer            varchar( 128 ) NOT NULL COMMENT "screen name of user" ,

    twitter_id          varchar( 128 ) NOT NULL COMMENT "ID of tweet" ,
    text                varchar( 140 ) NOT NULL COMMENT "text of tweet" ,
    created             varchar( 128 ) NOT NULL COMMENT "when in it was tweeted" ,
    retweeted           int(1) NOT NULL DEFAULT 0 ,

    user_id             varchar( 128 ) NOT NULL COMMENT "twitter ID num of tweeter" ,
    user_screen_name    varchar( 128 ) NOT NULL COMMENT "screen name of tweeter" ,
    user_name           varchar( 128 ) NOT NULL COMMENT "real name of tweeter" 
    )
    COMMENT="Stored favorited tweets"
    ENGINE=InnoDB
    ;


