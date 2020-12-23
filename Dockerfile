FROM node:latest

RUN mkdir -p /usr/local/ethaffairs

COPY . /usr/local/ethaffairs/

WORKDIR /usr/local/ethaffairs

RUN npm install

RUN echo blockchain_connection_string=${blockchain_connection_string} > .env

RUN npm run test