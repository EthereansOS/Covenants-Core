FROM node:latest

RUN mkdir -p /usr/local/ethaffairs

COPY . /usr/local/ethaffairs/

WORKDIR /usr/local/ethaffairs

RUN npm install

RUN npm run test