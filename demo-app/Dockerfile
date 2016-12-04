FROM node:argon-alpine

ENV NODE_ENV development

RUN mkdir -p /app
WORKDIR /app
COPY . /app
RUN npm install

VOLUME /app

EXPOSE 9999

CMD [ "node", "index.js" ]
