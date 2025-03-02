
package GeminiPage;

use warnings;
use strict;
use Exporter;
use List::Util qw(min max);
use Term::ANSIColor qw(RESET :constants);
use Term::ANSIScreen qw(:cursor :screen);
use Term::ReadKey;

our @ISA = qw(Exporter);
our @EXPORT_OK = qw(render_page_lines display_page get_next_scroll_line get_next_scroll_page get_scroll_end display_command_prompt set_command_error);

our $current_command_error = "";

sub apply_text_format
{
    my $text = $_[0];
    my $format = $_[1];
    
    my %text_formats = ("link"     => [BOLD, BLUE],
                        "heading1" => [BOLD, UNDERLINE, WHITE],
                        "heading2" => [BOLD, WHITE],
                        "heading3" => [UNDERLINE, WHITE],
                        "quote"    => [ITALIC, WHITE, ON_BRIGHT_BLACK]
    );
    
    my $format_ref = $text_formats{$format};
    return join("", @$format_ref) . $text . RESET;
}

sub wrap_words #(text, left_margin)
{
    my $text = $_[0];
    my $left_margin = $_[1];
    
    my @words = split(" ", $text);
    my ($chars_wide, $chars_high, $pixels_wide, $pixels_high) = GetTerminalSize();
    
    my $line_width = $left_margin;
    my @wrapped_lines;
    my @current_line_words;
    
    if (scalar(@words) == 0)
    {
        # this line was just whitespace, so display as a newline
        push(@wrapped_lines, "\n");
        return \@wrapped_lines;
    }
    
    for my $word (@words)
    {
        my $word_len = length($word);
        if ($line_width + $word_len > $chars_wide)
        {
            push(@wrapped_lines, join(" ", @current_line_words));
            @current_line_words = ();
            $line_width = $left_margin;
        }
        
        push(@current_line_words, $word);
        $line_width += $word_len;
        
        if ($line_width + 1 > $chars_wide) # if adding a space would be too wide
        {
            push(@wrapped_lines, join(" ", @current_line_words));
            @current_line_words = ();
            $line_width = $left_margin;
        }
        else
        {
            $line_width++;
        }
    }
    
    if (scalar(@current_line_words) > 0)
    {
        push(@wrapped_lines, join(" ", @current_line_words));
    }
    
    return \@wrapped_lines;
}

sub render_text_line #(text)
{
    my $text = $_[0];
    my $wrapped_lines_ref = wrap_words($text, 0);
    my @output;
    
    for my $line (@$wrapped_lines_ref)
    {
        if ($line ne "\n")
        {
            $line = "$line\n";
        }
        
        push(@output, "$line");
    }
    
    return \@output;
}

sub render_link_line #(text, url_num, page_urls_ref)
{
    my $text = $_[0];
    my $url_num = $_[1];
    my $page_urls_ref = $_[2];
    my @output;

    if ($text)
    {
        my $wrapped_lines_ref = wrap_words($text . " [$url_num]", 0);
        
        for my $line (@$wrapped_lines_ref)
        {
            $line = apply_text_format($line, "link");
            push(@output, "$line\n");
        }
    }
    else
    {
        # no friendly text, show the url instead
        my $line = apply_text_format($$page_urls_ref[$url_num - 1], "link");
        push(@output, "$line\n");
    }
    
    return \@output;
}

sub render_list_line #(text)
{
    my $text = $_[0];
    my $wrapped_lines_ref = wrap_words($text, 2);
    my @output;
    
    my $first_line = 1;
    for my $line (@$wrapped_lines_ref)
    {
        if ($first_line == 1)
        {
            push(@output, "• $line\n");
        }
        else
        {
            push(@output, "  $line\n");
        }
        
        $first_line = 0;
    }
    
    return \@output;
}

sub render_quote_line #(text)
{
    my $text = $_[0];
    my $wrapped_lines_ref = wrap_words($text, 0);
    my @output;
    
    for my $line (@$wrapped_lines_ref)
    {
        $line = apply_text_format($line, "quote");
        push(@output, "$line\n");
    }
    
    return \@output;
}

sub render_heading_line #(text, level)
{
    my $text = $_[0];
    my $level = $_[1];
    my $wrapped_lines_ref = wrap_words($text, 0);
    my @output;
    
    for my $line (@$wrapped_lines_ref)
    {
        $line = apply_text_format($line, "heading$level");
        push(@output, "$line\n");
    }
    
    return \@output;
}

sub render_page_lines #(parsed_page_content, page_urls_ref)
{
    my $page_content_ref = $_[0];
    my $page_urls_ref = $_[1];
    my $preformatted = 0;
    
    my @page_lines;
    
    for my $line_content_ref (@$page_content_ref)
    {
        my $type = $line_content_ref->{"line_type"};
        if ($type eq "pre")
        {
            $preformatted = not $preformatted;
        }
        elsif ($type eq "text")
        {
            # all preformatted lines are set as type text. if this line is preformatted, print as-is
            if ($preformatted)
            {
                push(@page_lines, $line_content_ref->{'text'});
            }
            else
            {
                my $rendered_ref = render_text_line($line_content_ref->{'text'});
                push(@page_lines, @$rendered_ref);
            }
        }
        elsif ($type eq "link")
        {
            my $rendered_ref = render_link_line($line_content_ref->{'text'}, $line_content_ref->{'url_num'}, $page_urls_ref);
            push(@page_lines, @$rendered_ref);
        }
        elsif ($type eq "li")
        {
            my $rendered_ref = render_list_line($line_content_ref->{'text'});
            push(@page_lines, @$rendered_ref);
        }
        elsif ($type eq "quote")
        {
            my $rendered_ref = render_quote_line($line_content_ref->{'text'});
            push(@page_lines, @$rendered_ref);
        }
        elsif ($type eq "heading")
        {
            my $rendered_ref = render_heading_line($line_content_ref->{'text'}, $line_content_ref->{'level'});
            push(@page_lines, @$rendered_ref);
        }
    }
    
    return \@page_lines;
}

sub display_page #(page_lines, scroll_height)
{
    my $page_lines_ref = $_[0];
    my $scroll_height = $_[1];
    
    my ($chars_wide, $chars_high, $pixels_wide, $pixels_high) = GetTerminalSize();
    
    locate();
    cldown();
    
    my $max_line_num = scalar(@$page_lines_ref) - 1;
    $scroll_height = max(min($scroll_height, $max_line_num - 1), 0);
    
    my $current_line_num = $scroll_height;
    my $lines_printed = 0;
    
    while ($current_line_num < $max_line_num and $lines_printed < $chars_high)
    {
        my $line = $$page_lines_ref[$current_line_num];
        if ($lines_printed == $chars_high - 1)
        {
            # last line at bottom of screen, don't want to end in a newline - but still need to include potential RESET
            $line =~ s/\n//;
        }
        
        print($line);

        $lines_printed++;
        $current_line_num++;
    }
    
    # return the actual scroll height being shown
    return $scroll_height;
}

sub get_next_scroll_line #(page_lines_ref, current_scroll, scroll_delta)
{
    my $page_lines_ref = $_[0];
    my $scroll_height = $_[1];
    my $scroll_delta = $_[2];
    
    my ($chars_wide, $chars_high, $pixels_wide, $pixels_high) = GetTerminalSize();
    
    my $max_line_num = scalar(@$page_lines_ref) - 1;
    $scroll_height = max(min($scroll_height + $scroll_delta, $max_line_num - 1), 0);
    
    return $scroll_height;
}

sub get_next_scroll_page #(page_lines_ref, current_scroll, scroll_dir)
{
    my $page_lines_ref = $_[0];
    my $scroll_height = $_[1];
    my $scroll_dir = $_[2];
    
    my ($chars_wide, $chars_high, $pixels_wide, $pixels_high) = GetTerminalSize();
    
    my $scroll_delta = $chars_high * $scroll_dir;
    return get_next_scroll_line($page_lines_ref, $scroll_height, $scroll_delta);
}

sub get_scroll_end #(page_lines_ref)
{
    my $page_lines_ref = $_[0];
    my $max_line_num = scalar(@$page_lines_ref) - 1;
    return $max_line_num - 1;
}

sub display_command_prompt #(prompt)
{
    my $prompt = $_[0];
    
    locate(1, 1);
    clline();
    
    locate(3, 1);
    clline();
    
    if ($current_command_error ne "")
    {
        print("Error: $current_command_error");
        locate(4, 1);
        clline();
    }
    
    locate(2, 1);
    clline();
    $prompt = "$prompt: ";
    print($prompt);
}

sub set_command_error
{
    $current_command_error = $_[0];
}

1;
