## Perl Plexity

RAG powered conversational search.

Uses Groq (LLama3) and Brave Search


```bash
#Update Perl if you haven't used it in a while
sudo apt-get update
sudo apt-get install build-essential
sudo apt-get install libssl-dev
sudo apt-get install zlib1g-dev
sudo CPAN -f

# Install dependencies
sudo cpan Mojolicious DBD::SQLite JSON Mojo::UserAgent Text::Markdown LWP::Protocol::https Env
```

Then run :)

```bash
perl app.pl daemon
#[info] Listening at "http://*:3000"
#Web application available at http://127.0.0.1:3000
```

### Screnshots

![Screenshot](/screenshot-main.png)
![Screenshot](/screenshot.png)


### Database
This project uses SQLite and creates a new app.db file in /data. To use another database, you must first install the db in your machine, then install the DBD driver, ie DBD::mysql, DBD::Pg
