# Microservice App - PRFT Devops Training

This is the application you are going to use through the whole traninig. This, hopefully, will teach you the fundamentals you need in a real project. You will find a basic TODO application designed with a [microservice architecture](https://microservices.io). Although is a TODO application, it is interesting because the microservices that compose it are written in different programming language or frameworks (Go, Python, Vue, Java, and NodeJS). With this design you will experiment with multiple build tools and environments. 

## Components
In each folder you can find a more in-depth explanation of each component:

1. [Users API](/users-api) is a Spring Boot application. Provides user profiles. At the moment, does not provide full CRUD, just getting a single user and all users.
2. [Auth API](/auth-api) is a Go application, and provides authorization functionality. Generates [JWT](https://jwt.io/) tokens to be used with other APIs.
3. [TODOs API](/todos-api) is a NodeJS application, provides CRUD functionality over user's TODO records. Also, it logs "create" and "delete" operations to [Redis](https://redis.io/) queue.
4. [Log Message Processor](/log-message-processor) is a queue processor written in Python. Its purpose is to read messages from a Redis queue and print them to standard output.
5. [Frontend](/frontend) Vue application, provides UI.

## Architecture

Take a look at the components diagram that describes them and their interactions.
![microservice-app-example](/arch-img/Microservices.png)


You should also:

For this project, you must work on both the development and operations sides,
considering the different aspects so that the project can be used by
an agile team. Initially, you must choose the agile methodology to use.
Aspects to consider for the development of the workshop:
1. 2.5% Branching strategy for developers
2. 2.5% Branching strategy for operations
3. 15.0% Cloud design patterns (minimum two)
4. 15.0% Architecture diagram
5. 15.0% Development pipelines (including scripts for tasks that require them)
6.5.0% Infrastructure pipelines (including scripts for tasks that require them)
7. 20.0% Infrastructure implementation
8. 15.0% Live demonstration of changes in the pipeline
9. 10.0% Delivery of results: must include the necessary documentation
for all developed elements.
Regarding patterns, consider using two of the following: cache aside,
circuit breaker, autoscaling, federated identity.

Translated with DeepL.com (free version)
