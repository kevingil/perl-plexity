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
my $dbh;
eval {
    $dbh = DBI->connect("dbi:SQLite:dbname=$db_file", '', '', { RaiseError => 1, AutoCommit => 1 });
};

if ($@) {
    warn "Failed to connect to database: $@";

    # Try to create the database directory if needed
    my $db_dir = './data';
    if (!-d $db_dir) {
        mkdir $db_dir or die "Could not create directory $db_dir: $!";
    }
    $dbh = DBI->connect("dbi:SQLite:dbname=$db_file", '', '', { RaiseError => 1, AutoCommit => 1 });

    if (!$dbh) {
        die "Failed to create database";
    }
}

# Setup schema
$dbh->do(<<'SQL');
CREATE TABLE IF NOT EXISTS search_thread (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    query TEXT NOT NULL,
    search_result TEXT NOT NULL
)
SQL

# Render a basic HTML layout
get '/' => sub {
  my $c = shift;
  
  # Render the layout with a dynamic component
  $c->render(
    inline => layout(),
    component => homepage(),
    format  => 'html'
  );
};

# Function that returns the main layout
sub layout {
  return <<'HTML';
<!DOCTYPE html>
<html lang="en">
<head>
  <title>App</title>
  <script src="https://unpkg.com/htmx.org@1.9.5/dist/htmx.min.js"></script>
  <script src="https://cdn.tailwindcss.com"></script>
</head>
<body class="bg-slate-900 text-white">
    <div>
    <h1 class="text-cyan-500 mx-auto max-w-2xl text-3xl font-normal px-2">
        perl-plexity
    </h1>  
    <div id="content">
        <%== $component %> <!-- This is where dynamic content will be inserted -->
    </div>
    </div>
</body>
</html>
HTML
}


# Function to render the homepage partial
sub homepage {
    my $searches;
    
    # Fetch tasks from the database
    $searches = $dbh->selectall_arrayref('SELECT * FROM search_thread', { Slice => {} });

    my $html = '<div class="p-2 mx-auto max-w-2xl">
      <p class="font-medium text-left my-4">Conversational knowledge</p>
      ';

    $html .= '<form hx-post="/search" hx-target="#content" hx-swap="innerHTML"
    class="p-2 flex gap-2 mb-4 relative" method="post">
        <textarea type="text" name="query" placeholder="Find answers..." class="bg-slate-700 w-full p-2 pb-10 border-1 border-slate-400 rounded" required></textarea>
        <button type="submit" class="absolute bottom-0 right-0 mb-4 mr-4  rounded border p-1 px-2 hover:bg-black/10">
        <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-4">
          <path stroke-linecap="round" stroke-linejoin="round" d="M13.5 4.5 21 12m0 0-7.5 7.5M21 12H3" />
        </svg>
        </button>
    </form>';

    $html .= '<ul class="mx-2">';
    foreach my $search (@$searches) {
        $html .= '<li class="rounded bg-slate-800 border-slate-600 border p-2 flex gap-2">';
        $html .= sprintf('<span class="w-full">%s</span>', $search->{query});
        $html .= sprintf('<button hx-get="/thread/%d" hx-target="#content" hx-swap="innerHTML" class="">Open</button>',
            $search->{id});
        $html .= sprintf('<button hx-post="/delete/%d" hx-target="#content" hx-swap="innerHTML" class="">Delete</button>',
            $search->{id});
        $html .= '</li>';
    }
    $html .= '</ul> </div>';

    return $html;
}


post '/search' => sub {
  my $c = shift;
  my $query = $c->param('query');
  my $brave_search = '';
  eval {
    $brave_search = request_web_search($query);
  };
  $dbh->do('INSERT INTO search_thread (query, search_result) VALUES (?, ?)', undef, $query, $brave_search);
  # After adding, re-render the list
  $c->render(inline => search_thread());
};


#Search thread content from history 
# with a follow up input box
get '/search/:id' => sub { 
  my $c = shift;
  my $id = $c->param('id');
  my $thread = $dbh->selectrow_hashref('SELECT * FROM search_thread WHERE id = ?', undef, $id);
  my $html = "<div><h2>Search Thread</h2><p>$thread->{query}</p><p>$thread->{search_result}</p></div>";
  $c->render(inline => $html);
};



#Renders the result of a search query
# with AI completion as the first chat message
# and follow up questions below
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


#Brave web/search 
# from https://api.search.brave.com/app/documentation/web-search/get-started
sub request_web_search {
    my ($query) = @_;
    my $api_key = $ENV{'BRAVE_API_KEY'}; 
    my $base_url = 'https://api.search.brave.com/res/v1/web/search';
    
    # Initialize the user agent
    my $ua = LWP::UserAgent->new();
    $ua->default_header('Accept' => 'application/json');
    $ua->default_header('Accept-Encoding' => 'gzip');
    $ua->default_header('X-Subscription-Token' => $api_key);
    
    # Build the request URL with the query parameter
    my $url = $base_url . "?q=" . $query;

    # Create the HTTP request
    my $request = HTTP::Request->new(GET => $url);
    
    # Send the request and get the response
    my $response = $ua->request($request);

    if ($response->is_success) {
        # Decode the JSON response
        my $content = $response->decoded_content;
        my $json_data = decode_json($content);

        return $json_data;  # Return the decoded JSON data
    } else {
        # Handle errors
        die "Request failed: " . $response->status_line;
    }
}

app->start;
