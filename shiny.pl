#!/usr/bin/perl

use strict;
use warnings;

use Scalar::Util qw(looks_like_number);
use Term::RawInput;
use Term::ANSIScreen qw(:cursor :screen);
use List::Util qw(min max);
use Time::HiRes qw(usleep);
use POSIX qw(ceil floor);

use lib(".");
use GeminiRequest qw(send_request make_and_send_request get_url_parts handle_url get_full_url);
use GeminiParser qw(parse_page);
use GeminiPage qw(render_page_lines display_page get_next_scroll_line get_next_scroll_page get_scroll_end display_command_prompt set_command_error);

our $SUCCESS = 1;
our $CANCELLED = 0;
our $FAILED = -1;

our $current_host = "";
our $current_page_dir = "";
our $current_page_content_ref = 0;
our $current_page_urls_ref = 0;
our $current_page_lines_ref = 0;
our $scroll_height = 0;

sub print_usage
{
    print("usage: \n");
    print("./shiny => blank page (press g to enter a url)\n");
    print("./shiny gemini://geminiprotocol.net => gemini://geminiprotocol.net\n");
    print("./shiny geminiprotocol.net => gemini://geminiprotocol.net\n");
    print("./shiny geminiprotocol.net/news => gemini://geminiprotocol.net/news\n");
}

sub create_page
{
    my $page_text = $_[0];
    
    ($current_page_content_ref, $current_page_urls_ref) = parse_page($page_text);
    $current_page_lines_ref = render_page_lines($current_page_content_ref, $current_page_urls_ref);
    $scroll_height = display_page($current_page_lines_ref, 0);
}

sub confirm_exit
{
    display_command_prompt("Confirm exit? [Y/n]");
    
    my $answer = <STDIN>;
    chomp($answer);
    if ($answer eq "y" or $answer eq "")
    {
        up();
        cldown();
        exit();
    }
}

sub navigate_link
{
    display_command_prompt("Link number");
    
    my $url_num = <STDIN>;
    chomp($url_num);
    if ($url_num eq "")
    {
        set_command_error("");
        return $CANCELLED;
    }
    
    if (not looks_like_number($url_num) or
        $url_num - int($url_num) != 0 or
        $url_num < 1)
    {
        set_command_error("please enter a number for the url to request");
        return $FAILED;
    }
    
    my $num_page_urls = scalar(@$current_page_urls_ref);
    if ($url_num > $num_page_urls)
    {
        set_command_error("url number too high, there are only $num_page_urls urls");
        return $FAILED;
    }
    
    my $url = $$current_page_urls_ref[$url_num - 1];
    my ($full_url, $ok) = get_full_url($url, $current_host, $current_page_dir);
    if (not $ok)
    {
        set_command_error($full_url);
        return $FAILED;
    }
    
    display_command_prompt("confirm request to $full_url [Y/n]");
    my $answer = lc(<STDIN>);
    chomp($answer);
    if ($answer ne "y" and $answer ne "")
    {
        set_command_error("");
        return $CANCELLED;
    }
    
    (undef, my $new_host, undef) = get_url_parts($full_url);
    (my $page_text, $ok) = handle_url($full_url, $new_host);
    
    if (not $ok)
    {
        set_command_error($page_text);
        return $FAILED;
    }
    else
    {
        create_page($page_text);
        (undef, $current_host, $current_page_dir) = get_url_parts($full_url);
        set_command_error("");
        return $SUCCESS;
    }
}


sub goto_url
{
    display_command_prompt("Enter URL");
    my $url = <STDIN>;
    chomp($url);
    
    if (length($url) == 0)
    {
        return $CANCELLED;
    }
    
    if (index($url, "gemini://") != 0)
    {
        $url = "gemini://" . $url;
    }

    (undef, my $new_host, undef) = get_url_parts($url);
    my ($page_text, $ok) = handle_url($url, $new_host);
    
    if (not $ok)
    {
        set_command_error("$page_text");
        return $FAILED;
    }
    else
    {
        create_page($page_text);
        (undef, $current_host, $current_page_dir) = get_url_parts($url);
        set_command_error("");
        return $SUCCESS;
    }
}

sub ease_scroll
{
    my $target_scroll_height = $_[0];
    my $start_scroll_height = $scroll_height;
    my $total_dif = $target_scroll_height - $start_scroll_height;
    if ($total_dif == 0)
    {
        return;
    }
    
    my $time_elapsed = 0;
    my $dt = 16666;
    my $duration = 500000; #nanoseconds
    my $cap_function;
    my $round_function;
    if ($total_dif < 0)
    {
        $cap_function = \&max;
        $round_function = \&floor;
    }
    else
    {
        $cap_function = \&min;
        $round_function = \&ceil;
    }
    
    while ($time_elapsed < $duration and $scroll_height != $target_scroll_height)
    {
        $time_elapsed += $dt;
        my $t = $time_elapsed / $duration;
        my $eased = 1 - 2**(-10 * $t);
        if ($t >= 1)
        {
            $eased = 1;
        }
        my $float_scroll_height = &$cap_function($start_scroll_height + $total_dif * $eased, $target_scroll_height);
        $scroll_height = &$round_function($float_scroll_height);
        #print("$t : $scroll_height\n");
        display_page($current_page_lines_ref, ($scroll_height));           
        usleep($dt);
    }
}


my $page_text = "";
my $ok = 0;

my $num_args = scalar(@ARGV);
if ($num_args == 0)
{
    # just have a blank page
    cls();
    my $result = $FAILED;
    while ($result == $FAILED)
    {
        $result = goto_url();
    }
    if ($result == $CANCELLED)
    {
        exit();
    }
}
elsif ($num_args == 1)
{
    my $url = $ARGV[0];
    if (index($url, "gemini://") != 0)
    {
        $url = "gemini://" . $url;
    }

    (undef, $current_host, $current_page_dir) = get_url_parts($url);
    ($page_text, $ok) = handle_url($url, $current_host);
    
    if (not $ok)
    {
        print("$page_text\n");
    }
    else
    {
        # test content
        # $page_text = "# heading 1\n## heading 2\n### heading 3\n#heading no space\n>funny and great quote\n* bullet\n* another bullet\n*not a bullet\n```\npreformat mode\n# header in preformat\n```\n=> urltoapage      text  with  \t  annoying variable  spaces\n=>       anotherurl";

        create_page($page_text);
    }
}
else
{
    print_usage();
    exit();
}

while (1)
{    
    my ($input, $key) = rawInput("", 1);
    
    if ($key eq "UPARROW")
    {
        my $target_scroll_height = get_next_scroll_line($current_page_lines_ref, $scroll_height, -5);
        ease_scroll($target_scroll_height);
    }
    
    if ($key eq "DOWNARROW")
    {
        my $target_scroll_height = get_next_scroll_line($current_page_lines_ref, $scroll_height, 5);
        ease_scroll($target_scroll_height);
    }
    
    if ($key eq "PAGEUP")
    {
        my $target_scroll_height = get_next_scroll_page($current_page_lines_ref, $scroll_height, -1);
        ease_scroll($target_scroll_height);
    }
    
    if ($key eq "PAGEDOWN")
    {
        my $target_scroll_height = get_next_scroll_page($current_page_lines_ref, $scroll_height, 1);
        ease_scroll($target_scroll_height);
    }
    
    if ($key eq "HOME")
    {
        my $target_scroll_height = 0;
        ease_scroll($target_scroll_height);
    }
    
    if ($key eq "END")
    {
        my $target_scroll_height = get_scroll_end($current_page_lines_ref);
        ease_scroll($target_scroll_height);
    }
    
    if ($input eq "q")
    {
        confirm_exit();
        display_page($current_page_lines_ref, $scroll_height);
    }
    
    if ($input eq "l")
    {
        my $result = $FAILED;
        while ($result == $FAILED)
        {
            $result = navigate_link();
        }
        
         if ($result == $CANCELLED)
        {
            display_page($current_page_lines_ref, $scroll_height);
        }
    }
    
    if ($input eq "g")
    {
        my $result = $FAILED;
        while ($result == $FAILED)
        {
            $result = goto_url();
        }
        
        if ($result == $CANCELLED)
        {
            
            display_page($current_page_lines_ref, $scroll_height);
        }
    }
}
