
package GeminiParser;

use warnings;
use strict;
use Exporter;
use builtin qw(trim);

our @ISA = qw(Exporter);
our @EXPORT_OK = qw(parse_page);


sub parse_page #(page_text)
{
    my $page_text = $_[0];
    my @lines = split("\n", $page_text);
    my @page_content;
    my @page_urls;
    my $preformatted = 0;
    
    for my $line (@lines)
    {
        if (length($line) < 3)
        {
            # not long enough to have a special type, or preformatted mode is enabled, so treat as text
            my %line_content = (line_type => "text", text => $line);
            push(@page_content, \%line_content);
            next;
        }
        
        my $line_start = substr($line, 0, 3);
        
        # checks for preformat must be first
        if ($line_start eq "```")
        {
            $preformatted = not $preformatted;
            my %line_content = (line_type => "pre");
            push(@page_content, \%line_content);
            next;
        }
        
        if ($preformatted == 1)
        {
            # force all text to have no further formatting
            my %line_content = (line_type => "text", text => $line);
            push(@page_content, \%line_content);
            next;
        }
        
        # check if line is a link
        if ($line_start eq "=> ")
        {
            # link of the form "=>[at least 1 whitespace][url][any amount of whitespace][optional friendly text for url]"
            # build the url one character at a time
            my $url = "";
            my $url_end = 3; # start from 3, after the "=> "
            my @line_chars = split("", substr($line, 3));
            my $initial_whitespace_cleared = 0;
            for my $char (@line_chars)
            {
                if ($char =~ /\s/)
                {
                    if ($initial_whitespace_cleared == 0)
                    {
                        # found a whitespace but url hasn't started yet
                        $url_end++;
                    }
                    else
                    {
                        # found a space after the start of the url, so end the url
                        last;
                    }
                }
                
                if ($char =~ /\S/)
                {
                    # found a letter, add it to the url
                    $initial_whitespace_cleared = 1;
                    $url = $url . $char;
                    $url_end++;
                }
            }
            
            # continue from the end of the url, go through all the characters until a non whitespace is found
            my $text_start = $url_end;
            @line_chars = split("", substr($line, $text_start));
            for my $char (@line_chars)
            {
                if ($char =~ /\S/)
                {
                    # found a non whitespace, so start the friendly text
                    last;
                }
                
                $text_start++;
            }
            
            push(@page_urls, $url); # want to push url first, so url_num starts from 1
            
            my $text = substr($line, $text_start);
            my %line_content = (line_type => "link", url_num => scalar(@page_urls), text => $text);
            push(@page_content, \%line_content);
            next;
        }
        
        # next checks want to look at individual characters
        my @line_start_chars = split("", $line_start);
        
        # check if line is a bullet point
        if ($line_start_chars[0] eq "*" and $line_start_chars[1] eq " ")
        {
            my %line_content = (line_type => "li", text => substr($line, 2));
            push(@page_content, \%line_content);
            next;
        }
        
        # check if line is a quote
        if ($line_start_chars[0] eq ">")
        {
            my %line_content = (line_type => "quote", text => substr($line, 1));
            push(@page_content, \%line_content);
            next;
        }
        
        # check if line is a heading, and if so what level
        if ($line_start_chars[0] eq "#")
        {
            my $heading_level = 1;
            if ($line_start_chars[1] eq "#")
            {
                $heading_level = 2;
                
                if ($line_start_chars[2] eq "#")
                {
                    $heading_level = 3;
                }
            }
            
            my $heading_text = substr($line, $heading_level);
            $heading_text =~ s/^\s+//; # remove the whitespace which may exist between the # and the text

            my %line_content = (line_type => "heading", level => $heading_level, text => $heading_text);
            push(@page_content, \%line_content);
            next;
        }
        
        # no special type, line is just text
        my %line_content = (line_type => "text", text => $line);
        push(@page_content, \%line_content);
    }
    
    return (\@page_content, \@page_urls);
}
