# Dockerfile
FROM perl:5.32

RUN sudo cpan Mojolicious DBD::SQLite

COPY . /app 
WORKDIR /app

CMD ["perl", "app.pl", "daemon"]
