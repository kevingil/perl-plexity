use strict;
use warnings;
use LWP::UserAgent;
use HTTP::Request;
use Mojolicious::Lite;
use JSON;
use DBI;


# Set up the SQLite database file path
my $db_file = './data/app.db';

# Try to connect to the SQLite database
my $dbh;
eval {
    $dbh = DBI->connect("dbi:SQLite:dbname=$db_file", '', '', { RaiseError => 1, AutoCommit => 1 });
};

# If the connection failed, handle the error
if ($@) {
    warn "Failed to connect to database: $@";

    # Try to create the database directory if needed
    my $db_dir = './data';
    if (!-d $db_dir) {
        mkdir $db_dir or die "Could not create directory $db_dir: $!";
    }

    # Re-attempt to connect
    $dbh = DBI->connect("dbi:SQLite:dbname=$db_file", '', '', { RaiseError => 1, AutoCommit => 1 });

    if (!$dbh) {
        die "Failed to connect to SQLite database after handling error";
    }
}

# Now that you have a connection, create the tasks table if it doesn't exist
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
<body>
    <div>
    <h1 class="mx-auto max-w-2xl text-3xl font-bold">
        get answers
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
    my $tasks;
    
    # Fetch tasks from the database
    $tasks = $dbh->selectall_arrayref('SELECT * FROM tasks', { Slice => {} });

    my $html = '<div class="p-2 mx-auto max-w-2xl">';

    $html .= '<form hx-post="/add" hx-target="#content" hx-swap="innerHTML"
    class="p-2 flex gap-2 mb-4" method="post">
        <input type="text" name="description" placeholder="New task" class="bg-gray/10 w-full px-2 border-2 rounded" required>
        <button type="submit" class="rounded border p-1 px-2 hover:bg-black/10">Add</button>
    </form>';

    $html .= '<ul>';
    foreach my $task (@$tasks) {
        $html .= '<li class="p-2 flex gap-2">';
        $html .= sprintf('<input type="checkbox" hx-post="/toggle/%d" hx-target="#content" hx-swap="innerHTML" %s>',
            $task->{id}, $task->{completed} ? 'checked' : '');
        $html .= sprintf('<span class="w-full">%s</span>', $task->{description});
        $html .= sprintf('<button hx-post="/delete/%d" hx-target="#content" hx-swap="innerHTML" class="">Delete</button>',
            $task->{id});
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
  }
  $dbh->do('INSERT INTO search_thread (query) VALUES (?)', undef, $query);
  # After adding, re-render the list
  $c->render(inline => search_thread());
};


#Search thread content from history 
# with a follow up input box
get '/search/:id' => sub { 
  
}



#Renders the result of a search query
# with AI completion as the first chat message
# and follow up questions below
sub search_thread {

} 


# Delete a search thread
post '/search/:id/delete' => sub {
  my $c = shift;
  my $id = $c->param('id');
  $dbh->do('DELETE FROM tasks WHERE id = ?', undef, $id);
  # Re-render the list after deleting
  $c->render(inline => homepage());
};


get '/search/new' => sub {
  my $c = shift
  $c->render(inline => new_thread_modal())
}

#Global modal to start a new chat thread
# can be used from anywhere in the app
#  on submit, redirects to /search/:id
sub new_thread_modal {

} 



#Brave web/search 
# from https://api.search.brave.com/app/documentation/web-search/get-started
sub request_web_search {
    my ($query) = @_;
    my $api_key = '<YOUR_API_KEY>'; 
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

sub request_groq_search_summary {
  my $question = shift;
  my $context = 
  return $question
}


app->start;
