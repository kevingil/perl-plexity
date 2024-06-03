use strict;
use warnings;
use HTTP::Request;
use LWP::Protocol::https;
use Mojolicious::Lite;
use Mojo::UserAgent;
use Mojo::IOLoop;
use URI::Escape;
use Text::Markdown 'markdown';
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
            user TEXT,
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

# Load .env
open my $env_file, '<', '.env' or die "No .env file: $!";
while (<$env_file>) {
    chomp;
    my ($key, $value) = split /=/, $_, 2;
    $ENV{$key} = $value;
}
close $env_file;


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
    <title>perl-plexity</title>
    <script src="https://unpkg.com/htmx.org@1.9.5/dist/htmx.min.js"></script>
    <script src="https://cdn.tailwindcss.com"></script>
    <style>

        ul, ol {
            list-style-type: disc !important;
            margin-top: 0.5rem !important;
            margin-bottom: 0.5rem !important;
            padding-left: 1rem !important;
        }


        .completion a {
            color: rgb(6 182 212);
            font-weight: bold !important;
        }

        @keyframes fade-in {
            from { opacity: 0; }
        }

        @keyframes fade-out {
            to { opacity: 0; }
        }

        @keyframes slide-from-right {
            from { transform: translateY(2rem); }
        }

        @keyframes slide-to-left {
            to { transform: translateY(2rem); }
        }

        .slide-content {
            view-transition-name: slide-content;
        }

        ::view-transition-old(slide-content) {
            animation: 180ms cubic-bezier(0,.74,0,.99) both fade-out,
            600ms cubic-bezier(0,.74,0,.99) both slide-to-left;
        }
        ::view-transition-new(slide-content) {
            animation: 420ms cubic-bezier(.26,.69,.21,.99) 90ms both fade-in,
            600ms cubic-bezier(.26,.69,.21,.99) both slide-from-right;
        }
        .fade-me-out.htmx-swapping {
        opacity: 0;
        transition: opacity 1s ease-out;
        }
        .fade-me-in.htmx-added {
        opacity: 0;
        }
        .fade-me-in {
        opacity: 1;
        transition: opacity 1s ease-out;
        }

    </style>
  </head>
  <body class="bg-zinc-900 text-white">
      <div class="">
      <div class="font-normal p-3 pb-4 rounded">
        <a hx-get="/" hx-target="#content" hx-swap="innerHTML transition:true" hx-push-url="true">
            <h1 class="max-w-2xl mx-auto text-left text-cyan-500 text-3xl cursor-pointer">
                perl-plexity
            </h1>
        </a>
      </div>
      
      <div id="content" class="">
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
  my $request_partial = $c->req->headers->header('HX-Request') ? 1 : 0;

  # Render layout and child component
  $c->render(
    inline => layout($request_partial),
    component => homepage(),
    format  => 'html'
  );
};


# Home component
sub homepage {
    my $searches = $dbh->selectall_arrayref('SELECT * FROM search_threads LIMIT 10', { Slice => {} });

    my $html = qq{
        <div class="p-2 mx-auto max-w-2xl slide-content">
            <p class="text-3xl text-left mx-4 my-10 font-light">Talk to the internet</p>
            <form id="query_form" hx-get="/search" hx-target="#content" hx-swap="innerHTML transition:true" hx-push-url="true" hx-trigger="" class="p-2 flex gap-2 mb-4 relative" method="post">
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
            <ul class="mx-2 p-0" style="list-style-type: none !important; padding-left: 0 !important;">
    };

    # Newest first
    foreach my $search ( reverse @$searches) {
        $html .= qq{
            <li>
                <div hx-get="/search/$search->{id}" hx-target="#content" hx-swap="innerHTML transition:true" hx-push-url="true" 
                    class="rounded hover:bg-zinc-700 bg-zinc-800 border-zinc-600 border p-2 mb-4 flex gap-2">
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


# New search thread request handler
get '/search' => sub {
    my $c = shift;
    my $user_query = $c->param('user_query');
    my $request_partial = $c->req->headers->header('HX-Request') ? 1 : 0;

    my $sth = $dbh->prepare('INSERT INTO search_threads (starting_query) VALUES (?)');
    $sth->execute($user_query);
    my $search_id = $dbh->last_insert_id;

    my $created_at = $dbh->selectrow_array('SELECT created_at FROM search_threads WHERE id = ?', undef, $search_id);

    my $html = <<"HTML";
    <div class="p-2 mx-auto max-w-2xl slide-content">
        <h1 id="queryid-$search_id" search_thread_id="$search_id" created-at="$created_at" class="text-4xl p-2">$user_query</h1>
        <div class="flex flex-col gap-2 mt-6">
            <div hx-get="/result?search_id=$search_id" hx-target="this" hx-swap="innerHTML" hx-trigger="load" class="rounded-md p-2 w-full mx-auto">
                <div class="flex gap-4 flex-row mb-8">
                    <div class="rounded bg-slate-700 h-20 w-[25%]"></div>
                    <div class="rounded bg-slate-700 h-20 w-[25%]"></div>
                    <div class="rounded bg-slate-700 h-20 w-[25%]"></div>
                    <div class="rounded bg-slate-700 h-20 w-[25%]"></div>
                </div>
                <div class="animate-pulse flex flex-col">
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

#Get existing search thread
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

    # Fetch search data from the database
    my $search_data = $dbh->selectrow_hashref('SELECT * FROM search_data WHERE search_thread_id = ? ORDER BY created_at DESC LIMIT 1', undef, $search_id);

    if (!$search_data) {
        $c->response->status(404);
        $c->response->body('Search data not found');
        return;
    }

    my $search_response = decode_json($search_data->{search_response});

    my $html = '<div class="p-2 mx-auto max-w-2xl slide-content">';
    $html .= "<h1 id=\"query_$search_id\" created-at=\"$created_at\" class=\"text-4xl p-2\">$user_query</h1>";
    $html .= '<div class="flex flex-col gap-2">';

    # Display search results
    $html .= '<div class="flex flex-row text-sm gap-2">';
    for my $result (@{$search_response->{web}->{results}}[0..2]) {
        $html .= '<div class="flex flex-col bg-zinc-700 hover:bg-zing-600 p-2 rounded w-[25%]">';
        $html .= "<a href=\"$result->{url}\" class='bold underline mb-1'>$result->{title}</a>";
        $html .= "<p class='text-xs max-h-4 overflow-hidden'>$result->{description}</p>";
        $html .= '</div>';
    }
    $html .= '</div>';

    # Display completion
    my $chat_content = $dbh->selectrow_hashref('SELECT * FROM chat_content WHERE search_thread_id = ? AND is_completion = 1 ORDER BY created_at DESC LIMIT 1', undef, $search_id);

    if ($chat_content) {
        my $content = $chat_content->{content};
        my $user = $chat_content->{user} // 'User';
        my $content_html = markdown($content);
        $html .= "<div class='fade-me-out fade-me-in completion'>";
        $html .= "<p class='text-sm text-gray-500 bold'>$user</p>";
        $html .= "<p class=''>$content_html</p>";
        $html .= "</div>";
    }

    $html .= '</div>';
    $html .= '</div>';

    $c->render(
        inline => layout($request_partial),
        component => $html,
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
    my $insert_sucess = $sth->execute($search_id, encode_json($api_response));
    my $api_response_json = encode_json($api_response);
    if (!$insert_sucess) {
        warn "Failed to insert search data: " . $dbh->errstr;
    }

    my $html = '<div class="p-2 mx-auto max-w-2xl">';
    $html .= '    <div class="flex flex-col gap-6">';
    $html .= "        <div id=\"result_$search_id\">";
    $html .= "            <h2 class='mb-2 bold'>Sources</h2>";
    $html .= '            <div class="flex flex-row text-sm gap-2">';

    for my $result (@{$api_response->{web}->{results}}[0..2]) {
        $html .= '                <div class="flex flex-col bg-zinc-700 hover:bg-zing-600 p-2 rounded w-[25%]">';
        $html .= "                    <a href=\"$result->{url}\" class='bold underline mb-1'>$result->{title}</a>";
        $html .= "                    <p class='text-xs max-h-4 overflow-hidden'>$result->{description}</p>";
        $html .= '                </div>';
    }

    $html .= '                <div class="flex flex-col bg-zinc-700 p-2 rounded w-[25%]">';
    $html .= "                    <a class='bold underline mb-1'>More sources</a>";
    $html .= "                    <p class='text-xs max-h-12 overflow-hidden'>Sources</p>";
    $html .= '                </div>';
    $html .= '            </div>';
    $html .= '        </div>';
    $html .= "        <div hx-get=\"/completion?search_id=$search_id\" hx-swap=\"transition:true\" hx-target=\"this\" hx-trigger=\"load\">";
    $html .= '            <div class="animate-pulse flex flex-col fade-me-out fade-me-in">';
    $html .= '                <div class="flex-1 mt-2 py-1">';
    $html .= '                    <div class="h-2 bg-slate-700 rounded"></div>';
    $html .= '                    <div class="mt-4">';
    $html .= '                        <div class="grid grid-cols-6 gap-4 mt-4">';
    $html .= '                            <div class="h-2 bg-slate-700 rounded col-span-2"></div>';
    $html .= '                            <div class="h-2 bg-slate-700 rounded col-span-4"></div>';
    $html .= '                        </div>';
    $html .= '                        <div class="h-2 bg-slate-700 rounded mt-4"></div>';
    $html .= '                    </div>';
    $html .= '                </div>';
    $html .= '                <div class="flex-1 mt-2 py-1">';
    $html .= '                    <div class="h-2 bg-slate-700 rounded"></div>';
    $html .= '                    <div class="mt-4">';
    $html .= '                        <div class="grid grid-cols-3 gap-4 mt-4">';
    $html .= '                            <div class="h-2 bg-slate-700 rounded col-span-2"></div>';
    $html .= '                            <div class="h-2 bg-slate-700 rounded col-span-1"></div>';
    $html .= '                        </div>';
    $html .= '                        <div class="h-2 bg-slate-700 rounded mt-4"></div>';
    $html .= '                    </div>';
    $html .= '                </div>';
    $html .= '            </div>';
    $html .= '        </div>';
    $html .= '    </div>';
    $html .= '  </div>';


    $c->render(
        inline => layout(1),
        component => $html,
        format  => 'html'
    );
};

# Endpoint to handle completion requests
get '/completion' => sub {
    my $c = shift;
    my $html;
    my $search_id = $c->param('search_id');
    my $user_query = $dbh->selectrow_array('SELECT starting_query FROM search_threads WHERE id = ?', undef, $search_id);
    my $search_data_json = $dbh->selectrow_array('SELECT search_response FROM search_data WHERE search_thread_id = ? ORDER BY created_at DESC LIMIT 1', undef, $search_id);
    my $search_data = decode_json($search_data_json);
    my $search_results = encode_json($search_data->{web}->{results});
    my $chat_history = $dbh->selectall_arrayref('SELECT content FROM chat_content WHERE search_thread_id = ? ORDER BY created_at ASC', { Slice => {} }, $search_id);

    my $completion = request_completion($user_query, $search_results, $chat_history, $c);    

    if ($completion->{errors}) {
        $html .= "<p class='text-xl'>Error: " . $completion->{errors} . '</p>';
    } else {
        my $content = $completion->{choices}->[0]->{message}->{content};
        my $content_html = markdown($content);
        my $model = $completion->{model};
        $html .= "<div class='fade-me-out fade-me-in completion'>";
        $html .= "<p class='text-sm text-gray-500 bold'>$model</p>"; 
        $html .= "<p class=''>$content_html</p>"; 
        $html .= "</div>";

        # Update chat_history with new completion
        my $search_data_id = $dbh->selectrow_array('SELECT id FROM search_data WHERE search_thread_id = ? ORDER BY created_at DESC LIMIT 1', undef, $search_id);
        my $sth = $dbh->prepare('INSERT INTO chat_content (search_thread_id, search_data_id, content, is_completion, user) VALUES (?, ?, ?, ?, ?)');
        $sth->execute($search_id, $search_data_id, $content, 1, $model); #LLM model as user
        push @{$chat_history}, { content => $content };
    }

    $c->render(
        inline => layout(1),
        component => $html,
        format  => 'html'
    );

};

#####################
#   API PROVIDERS   #
#####################

# Groq stream completion request
# https://console.groq.com/docs/quickst
sub request_completion {
    my ($user_query, $api_response_json, $chat_history, $c) = @_;
    my $errors = '';

    my $payload = {
        'messages' => [
            {
                'role'    => 'system',
                'content' => "You're a useful search assistant. You're expecting a question or query, using context, write a short comprehensive answer fasted on facts, no more than 100 words.
                 If there's nothing for you to answer, just write a short response. When applicable, quote your sources using available urls and titles. Use markdown. Search context: {$api_response_json}"
            },
            {
                'role'    => 'user',
                'content' => $user_query
            }
        ],
        'model'       => 'llama3-8b-8192',
        'temperature' => 1,
        'max_tokens'  => undef,
        'top_p'       => 1,
        'stream'      => Mojo::JSON->false,
        'stop'        => undef
    };

    my $ua = Mojo::UserAgent->new;

    my $res = $ua->post('https://api.groq.com/openai/v1/chat/completions' => { 'Authorization' => 'Bearer ' . $ENV{'GROQ_API_KEY'} } => json => $payload)->result;

    if ($res->is_success) {

        my $decoded_data;
        eval {
            $decoded_data = decode_json($res->body);
        };
        if ($@) {
            my $json_error = "Failed to decode JSON: $@";
            warn $json_error;
            return { errors => $json_error};
        }

        return $decoded_data;

    } else {
        my $error_message = "HTTP error: " . $res->message;
        warn $error_message;
        $errors .= $error_message . "\n";
        return { errors => $errors };
    }
}


sub send_sse_data {
    my ($c, $data) = @_;
    $c->write("data: $data\n\n");
    warn "Data sent: $data";
}

# Brave web search API
#    docs https://api.search.brave.com/app/documentation/web-search/get-started
sub request_web_search {
    my ($query) = @_;
    my $errors;
    my $api_key = $ENV{'BRAVE_API_KEY'};
    my $base_url = 'https://api.search.brave.com/res/v1/web/search';
    my $params = "?count=5&extra_snippets=true&result_filter=discussions,faq,infobox,news,query,web&q=";

    # Build request
    my $url = $base_url . $params . uri_escape($query);
    my $ua = Mojo::UserAgent->new();
    my $res = $ua->get($url => {
                 'User-Agent' => 'Application',
                 'Accept' => 'application/json',
                 'Accept-Encoding' => 'gzip',
                 'X-Subscription-Token' => $api_key
    })->result;

    if ($res->is_success) {
        my $content = $res->body;
        if (defined $content) {
            my $data = $res->json;
            return $data;
        } else {
            $errors = "Error parsing JSON";
            return { errors => $errors };
        }
    } else {
        # Handle errors
        $errors = "Request failed: " . $res->message;
        return { errors => $errors };
    }
}

# Scrape content from any URL
sub scrape_content {
    my ($url) = @_;
    my $ua = Mojo::UserAgent->new();
    my $res = $ua->get($url);

    if ($res->is_success) {
        my $content = $res->body;

        # Extract content between <body> tags
        if ($content =~ m|<body.*?>(.*?)</body>|is) {
            my $body_text = $1;

            # Remove extra tags and their content
            $body_text =~ s|<script.*?>.*?</script>||gis;
            $body_text =~ s|<nav.*?>.*?</nav>||gis;
            $body_text =~ s|<.*?>||g;

            return $body_text;
        } else {
            return "No article content.";
        }
    } else {
        return "No content available: " . $res->message;
    }
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
