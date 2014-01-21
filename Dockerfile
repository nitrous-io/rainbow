FROM ubuntu

ENV PATH /opt/nodejs/bin:$PATH
ENV RAINBOW_USERNAME app_runner
ENV HOME /home/${RAINBOW_USERNAME}

RUN apt-get update
RUN apt-get install -yy build-essential libpq-dev ntp curl git-core wget tar autoconf python-setuptools
RUN mkdir -p /opt/nodejs
RUN curl -s http://nodejs.org/dist/v0.8.25/node-v0.8.25-linux-x64.tar.gz | tar -v -C /opt/nodejs --strip-components=1 -xz
RUN curl https://npmjs.org/install.sh | clean=no sh

ADD github_rsa /root/.ssh/id_rsa
RUN echo "IdentityFile ~/.ssh/id_rsa" >> /etc/ssh/ssh_config
RUN echo "StrictHostKeyChecking no" >> /etc/ssh/ssh_config

RUN useradd -U -m $RAINBOW_USERNAME
WORKDIR /home/app_runner

ADD ./ ${HOME}/rainbow

RUN cd ${HOME}/rainbow && npm install

# Get rid of color in mocha for CI
RUN echo "--no-colors" >> ${HOME}/rainbow/test/mocha.opts
