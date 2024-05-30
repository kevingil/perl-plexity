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
my $dbh;
eval {
    $dbh = DBI->connect("dbi:SQLite:dbname=$db_file", '', '', { RaiseError => 1, AutoCommit => 1 });
};

# Create database if exists
if ($@) {
    warn "Building database: $@";

    my $db_dir = './data';
    if (!-d $db_dir) {
        mkdir $db_dir or die "Could not create directory $db_dir: $!";
    }
    $dbh = DBI->connect("dbi:SQLite:dbname=$db_file", '', '', { RaiseError => 1, AutoCommit => 1 });

    if (!$dbh) {
        die "Failed to create database";
    }
}

# Database schema
$dbh->do(<<'SQL');

-- Search threads table
CREATE TABLE IF NOT EXISTS search_threads (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Store user queries
CREATE TABLE IF NOT EXISTS user_queries (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    search_thread_id INTEGER,
    query TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (search_thread_id) REFERENCES search_threads(id) ON DELETE CASCADE
);

-- Store search API response
CREATE TABLE IF NOT EXISTS search_data (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_query_id INTEGER,
    search_response TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_query_id) REFERENCES user_queries(id) ON DELETE CASCADE
);

-- Store ChatGPT search summary
CREATE TABLE IF NOT EXISTS summaries (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_query_id INTEGER,
    search_data_id INTEGER,
    summary TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_query_id) REFERENCES user_queries(id) ON DELETE CASCADE,
    FOREIGN KEY (search_data_id) REFERENCES search_data(id) ON DELETE CASCADE
);

SQL


# Main HTML layout
sub layout {
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
        <h1 class="max-w-2xl mx-auto text-left text-cyan-500 text-3xl">
          perl-plexity
        </h1>  
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
    my $searches;
    
    # Fetch tasks from the database
    $searches = $dbh->selectall_arrayref('SELECT * FROM search_threads LIMIT 10', { Slice => {} });

    my $html = '<div class="p-2 mx-auto max-w-2xl">
      <p class="text-2xl text-left mx-4 my-10 font-light">Talk to the internet</p>
      ';

    $html .= '<form hx-post="/search" hx-target="#content" hx-swap="innerHTML"
                class="p-2 flex gap-2 mb-4 relative" method="post">
                <textarea type="text" name="query" placeholder="Find answers..." class="bg-zinc-700 w-full p-2 pb-10 border-2 border-zinc-400 rounded" required></textarea>
                <button type="submit" class="absolute bottom-0 right-0 mb-4 mr-4  rounded border p-1 px-2 hover:bg-black/10">
                  <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-4">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M13.5 4.5 21 12m0 0-7.5 7.5M21 12H3" />
                  </svg>
                </button>
              </form>';

    $html .= '<ul class="mx-2">';
    foreach my $search (@$searches) {
        $html .= sprintf('<li><div class="rounded hover:bg-zinc-700 bg-zinc-800 border-zinc-600 border p-2 mb-4 flex gap-2"
                  hx-get="/thread/%d" hx-target="#content" hx-swap="innerHTML">',
            $search->{id});
        $html .= sprintf('<span class="w-full">%s</span>', $search->{query});
        $html .= sprintf('<button hx-post="/delete/%d" hx-target="#content" hx-swap="innerHTML" class="hover:bg-zinc-800 text-zinc-600 border-zinc-600 pb-1 px-3 rounded border">x</button>',
            $search->{id});
        $html .= '</div></li>';
    }
    $html .= '</ul> </div>';

    return $html;
}

# Search request handler
get '/search' => sub {
    my $c = shift;
    my $user_query = $c->param('user_query');
    my $api_response = $c->param('api_response');
    my $chat_history = $c->param('chat_history');

    my $res = request_completion($user_query, $api_response, $chat_history);

    # Check if the response is successful
    if ($res->is_success) {
        # Set the appropriate headers for SSE
        $c->res->headers->content_type('text/event-stream');
        $c->res->headers->remove('Content-Length');
        $c->write_chunk("retry: 10000\n\n");

        # Stream the response data
        my $buffer = '';
        while (my $chunk = $res->read_entity_chunk) {
            $buffer .= $chunk;
            while ($buffer =~ /\n/) {
                my $line = substr($buffer, 0, index($buffer, "\n") + 1, '');
                send_sse_data($c, $line);
            }
        }
    }
    else {
        # Handle error case
        $c->render(text => 'Error: ' . $res->status_line);
    }

  $dbh->do('INSERT INTO search_threads (query, search_result) VALUES (?, ?)', undef, $user_query, $api_response);
  
  $c->render(inline => search_thread());


};



# Search content thread
get '/search/:id' => sub { 
  my $c = shift;
  my $id = $c->param('id');
  my $thread = $dbh->selectrow_hashref('SELECT * FROM search_threads WHERE id = ?', undef, $id);
  my $html = "<div><h2>Search Thread</h2><p>$thread->{query}</p><p>$thread->{search_result}</p></div>";
  $c->render(inline => $html);
};

sub search_thread {
  my $html = '<div>Search Thread Content Here</div>';
  return $html;
}


# Delete a search thread
post '/search/:id/delete' => sub {
  my $c = shift;
  my $id = $c->param('id');
  $dbh->do('DELETE FROM search_thread WHERE id = ?', undef, $id);
  # Re-render the list after deleting
  $c->render(inline => homepage());
};


# Renders search modal
get '/search/new' => sub {
  my $c = shift;
  $c->render(inline => new_thread_modal());
};

#Global modal to start a new chat thread
# can be used from anywhere in the app
#  on submit, redirects to /search/:id
sub new_thread_modal {
  return '<div>New Thread Modal Content Here</div>';
}



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
#   docs https://console.groq.com/docs/quickstart
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


app->start;
