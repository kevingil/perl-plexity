## Perl Single

Project template to make a single file, single page web app with Perl, HTMX, and Sqlite

To get started, install cpan dependencies.


```bash
# HTTP micro-framework and mysql drivers
sudo cpan Mojolicious DBD::SQLite JSON
```

Then run :)

```bash
perl app.pl daemon
```

### Database
This project uses SQLite and creates a new app.db file in /data. To use another database, you must first install the db in your machine, then install the DBD driver, ie DBD::mysql, DBD::Pg
