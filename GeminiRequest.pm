
package GeminiRequest;

use warnings;
use strict;
use Exporter;

use Net::SSLeay qw(sslcat);

our @ISA = qw(Exporter);
our @EXPORT_OK = qw(send_request make_and_send_request get_url_parts handle_url get_full_url);


sub get_url_parts #(url) -> (protocol, host, page_dir)
{
    my $url = $_[0];
    my $host = "";
    my $page_dir = "";
    my $protocol = "";
    
    my $protocol_end = index($url, "://");
    if ($protocol_end != -1)
    {
        $protocol = substr($url, 0, $protocol_end);
    }
    else
    {
        $protocol_end = -3;
    }
    
    my $host_start_index = $protocol_end + 3;
    my $without_protocol = substr($url, $host_start_index);
    
    my $host_end_index = index($without_protocol, "/");
    if ($host_end_index != -1)
    {
        $host = substr($without_protocol, 0, $host_end_index);
        
        my $page_dir_start_index = $host_end_index + 1;
        my $page_dir_end_index = rindex($without_protocol, "/");
        $page_dir = substr($without_protocol, $page_dir_start_index, $page_dir_end_index - $page_dir_start_index);
    }
    else
    {
        $host = $without_protocol;
    }
    
    return ($protocol, $host, $page_dir);
}

sub redirect #(request) -> (content, ok)
{
    my $request = $_[0];
    my (undef, $host, undef) = get_url_parts($request);
    
    print("redirecting to: $request\n");
    return send_request($host, "$request\r\n");
}

sub check_response #(response) -> (content, ok)
{
    my $response = $_[0];
    my $header_length = index($response, "\r\n");
    if ($header_length < 0)
    {
        $header_length = 0;
    }
    
    my $header = substr($response, 0, $header_length);
    # body may not exist, 
    my $first_space = index($header, " ");
    my $status = substr($header, 0, $first_space);
    my $meta = substr($header, $first_space + 1);

    if (substr($status, 0, 1) eq "2")
    {
        my $body = substr($response, index($response, "\n") + 1);
        return ($body, 1);
    }
    if (substr($status, 0, 1) eq "3")
    {
        return redirect($meta);
    }
    
    return ("Error: $response\n", 0);
}

sub send_request #(host, request) -> (content, ok)
{
    my $host = $_[0];
    my $request = $_[1];
    my $printable_request = substr($request, 0, -2);
    print("requesting: $printable_request on host $host\n");
    
    my $port = 1965;
    my ($response, $err) = sslcat($host, $port, $request);
    
    if ($err)
    {
        return ("request error: $err", 0);
    }
    
    return check_response($response);
}

sub make_and_send_request #(host, page) -> (content, ok)
{
    my $host = $_[0];
    my $page = $_[1];
    
    if (not $page or $page eq "/")
    {
        $page = "";
    }
    
    my $request = "gemini://$host/$page\r\n";
    return send_request($host, $request);
}

sub get_full_url #(url, host, page_dir)
{
    my $url = $_[0];
    my $host = $_[1];
    my $page_dir = $_[2];

    my $full_url;
    my $protocol;
    ($protocol, undef, undef) = get_url_parts($url);
    
    if ($protocol eq "")
    {
        #protocol not specified, so this is a relative url. check we have a current host
        if ($host eq "")
        {
            return ("relative url provided but no host", 0);
        }
        
        $protocol = "gemini"; # relative url will always use gemini page
        
        $full_url = "$protocol://$host";
        if ($page_dir)
        {
            $full_url = "$full_url/$page_dir";    
        }
        $full_url = "$full_url/$url";
    }
    else
    {
        $full_url = $url;
    }
    
    
    return ($full_url, 1);
}

sub handle_url #(url, host)
{
    my $url = $_[0];
    my $host = $_[1];
    
    (my $protocol, undef, undef) = get_url_parts($url);
    if ($protocol ne "gemini")
    {
        #todo: handle other protocols
        return ("non gemini url: $url", 0);
    }
    
    my $request = "$url\r\n";
    return send_request($host, $request);
}

1;
