use strict;
use warnings;
use LWP::UserAgent;
use HTTP::Request;
use Mojolicious::Lite;
use JSON;
use DBI;
use Env;


# SQLite setup
my $db_file = './data/app.db';

# Connection
my $dbh = eval {
    DBI->connect("dbi:SQLite:dbname=$db_file", '', '', { RaiseError => 1, AutoCommit => 1 });
};

# Create database if not exists
if ($@) {
    warn "Building database: $@";

    my $db_dir = './data';
    if (!-d $db_dir) {
        mkdir $db_dir or die "Could not create directory $db_dir: $!";
    }
    $dbh = DBI->connect("dbi:SQLite:dbname=$db_file", '', '', { RaiseError => 1, AutoCommit => 1 });
    die "Failed to create database" unless $dbh;

}

# Create database schema
$dbh->do('CREATE TABLE IF NOT EXISTS search_threads (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            starting_query TEXT NOT NULL
)');

$dbh->do('CREATE TABLE IF NOT EXISTS chat_content (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            search_thread_id INTEGER,
            search_data_id INTEGER,
            content TEXT NOT NULL,
            is_completion BOOLEAN NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (search_thread_id) REFERENCES search_threads(id) ON DELETE CASCADE,
            FOREIGN KEY (search_data_id) REFERENCES search_data(id) ON DELETE CASCADE
)');

$dbh->do('CREATE TABLE IF NOT EXISTS search_data (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            search_thread_id INTEGER,
            search_response TEXT NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (search_thread_id) REFERENCES search_threads(id) ON DELETE CASCADE
)');

# Test function
my $test_result = test_database();
print "$test_result\n";


# Main HTML layout
sub layout {
  my ($request_partial) = @_;
  
  return '<%== $component %>' if $request_partial;

  return <<'HTML';
  <!DOCTYPE html>
  <html lang="en">
  <head>
    <title>App</title>
    <script src="https://unpkg.com/htmx.org@1.9.5/dist/htmx.min.js"></script>
    <script src="https://cdn.tailwindcss.com"></script>
  </head>
  <body class="bg-zinc-900 text-white transition-all">
      <div>
      <div class="font-normal p-3 pb-4 rounded">
        <a href="/">
            <h1 class="max-w-2xl mx-auto text-left text-cyan-500 text-3xl">
                perl-plexity
            </h1>
        </a>
      </div>
      
      <div id="content">
          <%== $component %>
      </div>
      </div>
  </body>
  </html>
HTML
}


#################
#    ROUTING    #
#################


# Homepage
get '/' => sub {
  my $c = shift;
  
  # Render layout and child component
  $c->render(
    inline => layout(),
    component => homepage(),
    format  => 'html'
  );
};


# Home component
sub homepage {
    my $searches = $dbh->selectall_arrayref('SELECT * FROM search_threads LIMIT 10', { Slice => {} });

    my $html = qq{
        <div class="p-2 mx-auto max-w-2xl">
            <p class="text-2xl text-left mx-4 my-10 font-light">Talk to the internet</p>
            <form id="query_form" hx-get="/search" hx-target="#content" hx-swap="innerHTML" hx-push-url="true" hx-trigger="" class="p-2 flex gap-2 mb-4 relative" method="post">
                <textarea type="text" name="user_query" id="user_query" placeholder="Find answers..." class="bg-zinc-700 w-full p-2 pb-10 border-2 border-zinc-400 rounded" required></textarea>
                <button type="submit" class="absolute bottom-0 right-0 mb-4 mr-4 rounded border p-1 px-2 hover:bg-black/10">
                    <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-4">
                        <path stroke-linecap="round" stroke-linejoin="round" d="M13.5 4.5 21 12m0 0-7.5 7.5M21 12H3" />
                    </svg>
                </button>
            </form>
            <script>
                document.querySelector('textarea[name="user_query"]').addEventListener("keydown", function(event) {
                    if (event.key === "Enter" && !event.shiftKey) {
                        event.preventDefault();
                        this.form.requestSubmit();
                    }
                });
            </script>
            <ul class="mx-2">
    };

    foreach my $search (@$searches) {
        $html .= qq{
            <li>
                <div class="rounded hover:bg-zinc-700 bg-zinc-800 border-zinc-600 border p-2 mb-4 flex gap-2">
                    <span class="w-full">$search->{starting_query}</span>
                    <button hx-post="/search/delete/$search->{id}" hx-target="#content" hx-swap="innerHTML" hx-push-url="/"
                    onclick="event.stopPropagation();" class="hover:bg-zinc-800 text-zinc-600 border-zinc-600 pb-1 px-3 rounded border">x</button>
                </div>
            </li>
        };
    }

    $html .= '</ul> </div>';

    return $html;
}


# Search request handler
get '/search' => sub {
    my $c = shift;
    my $user_query = $c->param('user_query');
    my $request_partial = $c->req->headers->header('HX-Request') ? 1 : 0;

    my $sth = $dbh->prepare('INSERT INTO search_threads (starting_query) VALUES (?)');
    $sth->execute($user_query);
    my $search_id = $dbh->last_insert_id;

    my $created_at = $dbh->selectrow_array('SELECT created_at FROM search_threads WHERE id = ?', undef, $search_id);

    my $html = <<"HTML";
    <div class="p-2 mx-auto max-w-2xl">
        <h1 id="query_$search_id" search_thread_id="$search_id" created-at="$created_at" class="text-4xl p-2">$user_query</h1>
        <div class="flex flex-col gap-2 mt-6">
            <div class="shadow rounded-md p-2 w-full mx-auto">
                <div hx-get="/result?search_id=$search_id" hx-target="this" hx-swap="innerHTML" hx-trigger="load" class="flex gap-4 flex-row mb-8">
                    <div class="rounded bg-slate-700 h-20 w-[25%]"></div>
                    <div class="rounded bg-slate-700 h-20 w-[25%]"></div>
                    <div class="rounded bg-slate-700 h-20 w-[25%]"></div>
                    <div class="rounded bg-slate-700 h-20 w-[25%]"></div>
                </div>
                <div x-get="/completion?search_id=$search_id" hx-target="this" hx-swap="innerHTML" hx-trigger=" " class="animate-pulse flex flex-col">
                    <div class="flex-1 mt-2 py-1">
                        <div class="h-2 bg-slate-700 rounded"></div>
                        <div class="mt-4">
                            <div class="grid grid-cols-6 gap-4 mt-4">
                                <div class="h-2 bg-slate-700 rounded col-span-2"></div>
                                <div class="h-2 bg-slate-700 rounded col-span-4"></div>
                            </div>
                            <div class="h-2 bg-slate-700 rounded mt-4"></div>
                        </div>
                    </div>
                    <div class="flex-1 mt-2 py-1">
                        <div class="h-2 bg-slate-700 rounded"></div>
                        <div class="mt-4">
                            <div class="grid grid-cols-3 gap-4 mt-4">
                                <div class="h-2 bg-slate-700 rounded col-span-2"></div>
                                <div class="h-2 bg-slate-700 rounded col-span-1"></div>
                            </div>
                            <div class="h-2 bg-slate-700 rounded mt-4"></div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </div>
HTML

    $c->render(
        inline => layout($request_partial),
        component => $html,
        format  => 'html'
    );
};

# Get search thread by ID
get '/search/:id' => sub {
    my $c = shift;
    my $search_id = $c->stash('id');
    my $request_partial = $c->req->headers->header('HX-Request') ? 1 : 0;

    my $search_info = $dbh->selectrow_hashref('SELECT * FROM search_threads WHERE id = ?', undef, $search_id);

    if (!$search_info) {
        $c->response->status(404);
        $c->response->body('Search info not found');
        return;
    }

    my $user_query = $search_info->{starting_query};
    my $created_at = $search_info->{created_at};

    my $html = <<"HTML";
    <div class="p-2 mx-auto max-w-2xl">
        <h1 id="query_$search_id" created-at="$created_at" class="text-4xl p-2">$user_query</h1>
        <div class="flex flex-col gap-2">
            <!-- Follow up messages will be inserted here -->
        </div>
    </div>
HTML

    $c->render(
        inline => layout($request_partial),
        component => $html,
        format  => 'html'
    );
};



# Delete a search thread
post '/search/delete/:id' => sub {
    my $c = shift;
    my $id = $c->param('id');
    $dbh->do('DELETE FROM search_threads WHERE id = ?', undef, $id);
    # Re-render the list after deleting
    $c->render(
        inline => layout(1),
        component => homepage(),
        format  => 'html'
    );
  
};


# Render search result, sources, start text completion stream
get '/result' => sub {
    my $c = shift;
    my $search_id = $c->param('search_id');
    my $user_query = $dbh->selectrow_array('SELECT starting_query FROM search_threads WHERE id = ?', undef, $search_id);

    my $api_response = request_web_search($user_query);
    my $sth = $dbh->prepare('INSERT INTO search_data (search_thread_id, search_response) VALUES (?, ?)');
    $sth->execute($search_id, encode_json($api_response));
    my $search_data_id = $dbh->last_insert_id;

    my $html = '<div class="p-2 mx-auto max-w-2xl">';
    $html .= "<h1 id=\"query_$search_id\" class=\"text-4xl p-2\">$user_query</h1>";
    $html .= '<div class="flex flex-col gap-2">';
    $html .= "<div id=\"answer_$search_id\">$api_response->{web}{results}[0]{snippet}</div>";
    $html .= '<div id="summary"></div>';
    $html .= '</div></div>';

    $c->render(
        inline => layout(1),
        component => $html,
        format  => 'html'
    );
};

# Completion stream to summarize search response
get '/summary' => sub {
    my $c = shift;
    my $search_id = $c->param('search_id');
    my $user_query = $dbh->selectrow_array('SELECT starting_query FROM search_threads WHERE id = ?', undef, $search_id);
    my $search_data = $dbh->selectrow_array('SELECT search_response FROM search_data WHERE search_thread_id = ? ORDER BY created_at DESC LIMIT 1', undef, $search_id);
    my $api_response = decode_json($search_data);

    my $chat_history = $dbh->selectall_arrayref('SELECT content FROM chat_content WHERE search_thread_id = ? ORDER BY created_at ASC', undef, $search_id);

    my $res = request_completion($user_query, $api_response, $chat_history);

    $c->res->headers->header('Content-Type' => 'text/event-stream');
    $c->res->headers->header('Cache-Control' => 'no-cache');

    while ($res->is_success) {
        my $buffer;
        $res->read($buffer, 1024);
        my $data = decode_json($buffer);
        foreach my $choice (@{$data->{choices}}) {
            if (exists $choice->{delta}->{content}) {
                send_sse_data($c, $choice->{delta}->{content});
                my $sth = $dbh->prepare('INSERT INTO chat_content (search_thread_id, search_data_id, content, is_completion) VALUES (?, ?, ?, ?)');
                $sth->execute($search_id, $search_data->{search_data_id}, $choice->{delta}->{content}, 1);
            }
        }
    }
};


#####################
#   API PROVIDERS   #
#####################


# Brave web search API
#    docs https://api.search.brave.com/app/documentation/web-search/get-started
sub request_web_search {
    my ($query) = @_;
    my $errors;
    my $api_key = $ENV{'BRAVE_API_KEY'}; 
    my $base_url = 'https://api.search.brave.com/res/v1/web/search';
    
    # Build HTTP request
    my $ua = LWP::UserAgent->new();
    $ua->default_header('Accept' => 'application/json');
    $ua->default_header('Accept-Encoding' => 'gzip');
    $ua->default_header('X-Subscription-Token' => $api_key);

    my $url = $base_url . "?q=" . $query;
    
    # Send request
    my $request = HTTP::Request->new(GET => $url);
    
    # Get response
    my $response = $ua->request($request);

    # Decode JSON
    if ($response->is_success) {
        my $content = $response->decoded_content;
        my $json_data = decode_json($content);
        return $json_data; 
    } else {
        # Handle errors
        $errors = "Request failed: " . $response->status_line;
        return { errors => $errors };
    }
}

# Helper function to send SSE data
sub send_sse_data {
    my ($c, $data) = @_;
    $c->write_chunk("data: $data\n\n");
}

# Groq stream completion request
#   docs https://console.groq.com/docs/quickst
sub request_completion {
    my ($user_query, $api_response, $chat_history) = @_;

    # Set up the user agent and request
    my $ua = LWP::UserAgent->new();
    my $req = HTTP::Request->new('POST', 'https://api.groq.com/openai/v1/chat/completions');
    $req->header('Content-Type' => 'application/json');

    # Prepare the payload
    my $payload = {
        'messages' => [
            {
                'role' => 'system',
                'content' => "You are the internet speaking in natural language,
                            using the search API response data, answer the user question.
                            Chat history is also provided for context. {$api_response} {$chat_history}"
            },
            {
                'role' => 'user',
                'content' => $user_query
            }
        ],
        'model' => 'llama3-8b-8192',
        'temperature' => 1,
        'max_tokens' => 1024,
        'top_p' => 1,
        'stream' => JSON::true,
        'stop' => undef
    };

    $req->content(encode_json($payload));

    # Send request and handle response
    my $res = $ua->request($req);

    return $res;
}


########
# TEST #
########

# Test database 
sub test_database {
    # Create a new search thread
    my $sth = $dbh->prepare('INSERT INTO search_threads (starting_query) VALUES (?)');
    $sth->execute('Test query');
    my $search_id = $dbh->last_insert_id;
    return 'Error creating search thread' unless $search_id;

    # Insert data into the search_data table
    $sth = $dbh->prepare('INSERT INTO search_data (search_thread_id, search_response) VALUES (?, ?)');
    $sth->execute($search_id, 'Test search response');
    my $search_data_id = $dbh->last_insert_id;
    return 'Error inserting search data' unless $search_data_id;

    # Insert chat content
    $sth = $dbh->prepare('INSERT INTO chat_content (search_thread_id, search_data_id, content, is_completion) VALUES (?, ?, ?, ?)');
    $sth->execute($search_id, $search_data_id, 'Test chat content', 1);
    my $chat_content_id = $dbh->last_insert_id;
    return 'Error inserting chat content' unless $chat_content_id;

    # Delete the search thread to clean up
    $dbh->do('DELETE FROM search_threads WHERE id = ?', undef, $search_id);
    my $deleted_rows = $dbh->rows;
    return 'Error deleting search thread' unless $deleted_rows;

    return 'All tests passed';
}


app->start;
