FROM node:latest

RUN npm install -g truffle
RUN npm install -g ganache-cli

RUN mkdir -p /usr/local/ethaffairs

COPY . /usr/local/ethaffairs/

WORKDIR /usr/local/ethaffairs
RUN cp entrypoint.sh .
RUN chmod +x entrypoint.sh

ENTRYPOINT ["./entrypoint.sh"] 