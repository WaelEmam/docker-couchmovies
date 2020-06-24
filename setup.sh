#!/bin/bash

if [ -z $DEMO_DIR ];then
	export DEMO_DIR=/couchmovies
fi

if [ -z $CONTAINER ];then
	export CONTAINER=couchmovies
fi

if [ -z $IMAGE ];then
	export IMAGE=couchmovies
fi

if [ -z $CB_SERVER ];then
	export CB_SERVER=127.0.0.1
fi

export CB_ENGINE=couchbase://$CB_SERVER

if [ -z $CB_USER ];then
	export CB_USER=Administrator
fi

if [ -z $CB_PASSWORD ];then
	export CB_PASSWORD=password
fi

if [ -z $CB_MOVIE_BUCKET ];then
	export CB_MOVIE_BUCKET=moviedata
fi

if [ -z $CB_TWEET_SOURCE_BUCKET ];then
	export CB_TWEET_SOURCE_BUCKET=tweetsource
fi

if [ -z $CB_TWEET_TARGET_BUCKET ];then
	export CB_TWEET_TARGET_BUCKET=tweettarget
fi


#Load Data
unzip ${DEMO_DIR}/data/moviedata.zip
cbimport json -c $CB_ENGINE -u $CB_USER -p $CB_PASSWORD -b $CB_MOVIE_BUCKET -d file:///moviedata.json  -f lines -g %type%::%id% -t 4
#rm ${DEMO_DIR}/data/moviedata.json

unzip ${DEMO_DIR}/data/tweetsource.zip
cbimport json -c $CB_ENGINE -u $CB_USER -p $CB_PASSWORD -b $CB_TWEET_SOURCE_BUCKET -d file:///tweetsource.json  -f lines -g historic::%tweetId% -t 4
#rm ${DEMO_DIR}/data/tweetsource.json

cbq -e $CB_ENGINE -u $CB_USER -p $CB_PASSWORD --script "CREATE PRIMARY INDEX ON ${CB_MOVIE_BUCKET}"
sleep 15s
cbq -e $CB_ENGINE -u $CB_USER -p $CB_PASSWORD --script "CREATE PRIMARY INDEX ON ${CB_TWEET_SOURCE_BUCKET}"
sleep 15s
cbq -e $CB_ENGINE -u $CB_USER -p $CB_PASSWORD --script "CREATE INDEX idx_type ON ${CB_MOVIE_BUCKET}(type) WITH {\"defer_build\":true}"
sleep 15s
cbq -e $CB_ENGINE -u $CB_USER -p $CB_PASSWORD --script "CREATE INDEX idx_primaryName ON ${CB_MOVIE_BUCKET}(type,primaryName,birthYear) WHERE type = 'person' WITH {'defer_build':true}"
sleep 15s
cbq -e $CB_ENGINE -u $CB_USER -p $CB_PASSWORD --script "CREATE INDEX idx_castName ON ${CB_MOVIE_BUCKET}((distinct (array (c.name) for c in \`cast\` end))) WHERE type = 'movie' WITH {'defer_build':true}"
sleep 15s
cbq -e $CB_ENGINE -u $CB_USER -p $CB_PASSWORD --script "CREATE INDEX idx_movieTitle ON ${CB_MOVIE_BUCKET}(type,title,revenue) WHERE type = 'movie' WITH {'defer_build':true}"
sleep 15s
cbq -e $CB_ENGINE -u $CB_USER -p $CB_PASSWORD --script "BUILD INDEX ON ${CB_MOVIE_BUCKET}(idx_type, idx_primaryName, idx_castName, idx_movieTitle) USING GSI"

curl -XPUT -H "Content-type:application/json" http://$CB_USER:$CB_PASSWORD@${CB_SERVER}:8094/api/index/movies_shingle -d @$DEMO_DIR/indexes/movies_shingle.json
curl -XPUT -H "Content-type:application/json" http://$CB_USER:$CB_PASSWORD@${CB_SERVER}:8094/api/index/movies_autocomplete -d @$DEMO_DIR/indexes/movies_autocomplete.json

couchbase-cli user-manage -c ${CB_SERVER}:8091 -u ${CB_USER} \
 -p ${CB_PASSWORD} --set --rbac-username ${CB_MOVIE_BUCKET} --rbac-password password \
 --rbac-name "moviedata" --roles fts_searcher[${CB_MOVIE_BUCKET}],data_reader[${CB_MOVIE_BUCKET}],query_manage_index[${CB_MOVIE_BUCKET}],bucket_full_access[${CB_MOVIE_BUCKET}] \
 --auth-domain local

couchbase-cli user-manage -c ${CB_SERVER}:8091 -u ${CB_USER} \
 -p ${CB_PASSWORD} --set --rbac-username ${CB_TWEET_SOURCE_BUCKET} --rbac-password password \
 --rbac-name "tweetsource" --roles bucket_full_access[${CB_TWEET_SOURCE_BUCKET}] \
 --auth-domain local

couchbase-cli user-manage -c ${CB_SERVER}:8091 -u ${CB_USER} \
 -p ${CB_PASSWORD} --set --rbac-username ${CB_TWEET_TARGET_BUCKET} --rbac-password password \
 --rbac-name "tweettarget" --roles bucket_full_access[${CB_TWEET_TARGET_BUCKET}] \
 --auth-domain local
echo "waiting for 120 seconds"
sleep 120

mv /couchmovies/src/main/resources/application.properties /couchmovies/src/main/resources/application.properties.bkup
echo "spring.couchbase.bootstrap-hosts=${CB_SERVER}" > /couchmovies/src/main/resources/application.properties
echo "spring.couchbase.bucket.name=${CB_MOVIE_BUCKET}" >> /couchmovies/src/main/resources/application.properties
echo "spring.couchbase.bucket.user=${CB_MOVIE_BUCKET}" >> /couchmovies/src/main/resources/application.properties
echo "spring.couchbase.bucket.password=password" >> /couchmovies/src/main/resources/application.properties
echo "spring.data.couchbase.auto-index=true" >> /couchmovies/src/main/resources/application.properties

cd /couchmovies
mvn clean install

#sudo cp ./services/movieservice /etc/init.d/movieservice
#sudo chmod +x /etc/init.d/movieservice
#sudo update-rc.d movieservice defaults
#sudo service movieservice start

sudo cp ./services/movieserver /etc/init.d/movieserver
sudo chmod +x /etc/init.d/movieserver
sudo update-rc.d movieserver defaults
sudo service movieserver start

cd /couchmovies
mvn spring-boot:run > couchmovies.log 2>&1 &

#Not ending process for container to run
tail -f /dev/null
