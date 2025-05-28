#!/bin/bash
# build-and-push.sh
# Usage: ./build-and-push.sh
# Builds and pushes client and server images to Docker Hub with proper tags

set -e

DOCKERHUB_USER=chirag117
CLIENT_IMAGE=$DOCKERHUB_USER/gen-client:v1
SERVER_IMAGE=$DOCKERHUB_USER/gen-serv:v1

# Build client image

echo "Building client image..."
docker build -f client/next.dockerfile -t $CLIENT_IMAGE ./client

echo "Building server image..."
docker build -f server/node.dockerfile -t $SERVER_IMAGE ./server

# Push images to Docker Hub

echo "Pushing client image to Docker Hub..."
docker push $CLIENT_IMAGE

echo "Pushing server image to Docker Hub..."
docker push $SERVER_IMAGE

echo "Build and push complete!"
