# syntax = docker/dockerfile:1

FROM node:12-alpine AS base

WORKDIR /src
COPY package*.json ./
RUN npm ci

COPY .eslintrc.json .prettierrc ./
COPY os ./os
COPY hup ./hup

FROM base AS lint
RUN npm run lint

FROM base AS prettify
RUN --mount=type=bind,src=./os,target=./os,rw \
    --mount=type=bind,src=./hup,target=./hup,rw \
    npm run prettify
