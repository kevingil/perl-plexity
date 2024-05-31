## Perl Plexity

AI powered conversational search.

Uses Groq (LLama3) and Brave Search


```bash
#Update Perl if you haven't used it in a while
sudo apt-get update
sudo apt-get install build-essential
sudo CPAN 
>install CPAN
>reload cpan

# Install dependencies
# HTTP micro-framework, mysql drivers, etc
sudo cpan Mojolicious DBD::SQLite JSON LWP::UserAgent Env
```

Then run :)

```bash
perl app.pl daemon
[info] Listening at "http://*:3000"
Web application available at http://127.0.0.1:3000
```

### Database
This project uses SQLite and creates a new app.db file in /data. To use another database, you must first install the db in your machine, then install the DBD driver, ie DBD::mysql, DBD::Pg
