#Couchmovies Application Server
FROM couchbase:latest
MAINTAINER wael@couchbase.com

RUN apt-get update
RUN apt-get -y  install git sudo
RUN useradd -m -p $(openssl passwd -1 demo) demo
RUN usermod -aG sudo demo
RUN echo '%sudo ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers
RUN echo "PATH=/opt/couchbase/bin:\$PATH" >> /home/demo/.profile
RUN su -l demo
RUN git clone https://github.com/craig-kovar/couchmovies.git

RUN sudo apt-get -y install zip unzip jq maven vim openjdk-8-jdk python chromium-chromedriver
RUN sudo ln -s /usr/lib/chromium-browser/chromedriver /usr/local/bin/chromedriver

COPY setup.sh /
RUN chmod +x /setup.sh
ENTRYPOINT ["/setup.sh"]

EXPOSE 8000 8080
