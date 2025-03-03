
package GeminiPage;

use warnings;
use strict;
use Exporter;
use List::Util qw(min max);
use Term::ANSIColor qw(RESET :constants);
use Term::ANSIScreen qw(:cursor :screen);
use Term::ReadKey;

use lib(".");
use Log qw(log_write);

our @ISA = qw(Exporter);
our @EXPORT_OK = qw(render_page_lines display_page get_next_scroll_line get_next_scroll_page get_scroll_end display_command_prompt set_command_prompt set_command_error find_line_num_of_word_num);

our $current_command_prompt = "";
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
    
    my $current_line_num_words = 0;
    my @num_words_in_line;
    
    if (scalar(@words) == 0)
    {
        # this line was just whitespace, so display as a newline
        push(@wrapped_lines, "\n");
        push(@num_words_in_line, 1);
        return (\@wrapped_lines, \@num_words_in_line);
    }
    
    for my $word (@words)
    {
        my $word_len = length($word);
        if ($line_width + $word_len > $chars_wide)
        {
            push(@wrapped_lines, join(" ", @current_line_words));
            push(@num_words_in_line, $current_line_num_words);
            @current_line_words = ();
            $current_line_num_words = 0;
            $line_width = $left_margin;
        }
        
        push(@current_line_words, $word);
        $current_line_num_words++;
        $line_width += $word_len;
        
        if ($line_width + 1 > $chars_wide) # if adding a space would be too wide
        {
            push(@wrapped_lines, join(" ", @current_line_words));
            push(@num_words_in_line, $current_line_num_words);
            @current_line_words = ();
            $current_line_num_words = 0;
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
        push(@num_words_in_line, $current_line_num_words);
    }
    
    return (\@wrapped_lines, \@num_words_in_line);
}

sub render_text_line #(text)
{
    my $text = $_[0];
    my ($wrapped_lines_ref, $num_words_in_line_ref) = wrap_words($text, 0);
    my @output;
    
    for my $line (@$wrapped_lines_ref)
    {
        if ($line ne "\n")
        {
            $line = "$line\n";
        }
        
        push(@output, "$line");
    }
    
    return (\@output, $num_words_in_line_ref);
}

sub render_link_line #(text, url_num, page_urls_ref)
{
    my $text = $_[0];
    my $url_num = $_[1];
    my $page_urls_ref = $_[2];
    my @output;

    if ($text)
    {
        my ($wrapped_lines_ref, $num_words_in_line_ref) = wrap_words($text . " [$url_num]", 0);
        
        for my $line (@$wrapped_lines_ref)
        {
            $line = apply_text_format($line, "link");
            push(@output, "$line\n");
        }
        
        return (\@output, $num_words_in_line_ref);
    }
    else
    {
        # no friendly text, show the url instead
        my $line = apply_text_format($$page_urls_ref[$url_num - 1], "link");
        push(@output, "$line\n");
        my @num_words_in_line = [1];
        
        return (\@output, \@num_words_in_line);
    }
}

sub render_list_line #(text)
{
    my $text = $_[0];
    my ($wrapped_lines_ref, $num_words_in_line_ref) = wrap_words($text, 2);
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
    
    return (\@output, $num_words_in_line_ref);
}

sub render_quote_line #(text)
{
    my $text = $_[0];
    my ($wrapped_lines_ref, $num_words_in_line_ref) = wrap_words($text, 0);
    my @output;
    
    for my $line (@$wrapped_lines_ref)
    {
        $line = apply_text_format($line, "quote");
        push(@output, "$line\n");
    }
    
    return (\@output, $num_words_in_line_ref);
}

sub render_heading_line #(text, level)
{
    my $text = $_[0];
    my $level = $_[1];
    my ($wrapped_lines_ref, $num_words_in_line_ref) = wrap_words($text, 0);
    my @output;
    
    for my $line (@$wrapped_lines_ref)
    {
        $line = apply_text_format($line, "heading$level");
        push(@output, "$line\n");
    }
    
    return (\@output, $num_words_in_line_ref);
}

sub render_page_lines #(parsed_page_content, page_urls_ref)
{
    my $page_content_ref = $_[0];
    my $page_urls_ref = $_[1];
    my $preformatted = 0;
    
    my @page_lines;
    my @num_words_before_line;
    my $num_words_so_far = 0;
    
    for my $line_content_ref (@$page_content_ref)
    {
    
        my $rendered_ref;
        my $num_words_in_lines_ref;
        my $type = $line_content_ref->{"line_type"};
        if ($type eq "pre")
        {
            $preformatted = not $preformatted;
            next;
        }
        elsif ($type eq "text")
        {
            # all preformatted lines are set as type text. if this line is preformatted, print as-is
            if ($preformatted)
            {
                push(@page_lines, $line_content_ref->{"text"});
                next;
            }
            else
            {
                ($rendered_ref, $num_words_in_lines_ref) = render_text_line($line_content_ref->{"text"});
            }
        }
        elsif ($type eq "link")
        {
            ($rendered_ref, $num_words_in_lines_ref) = render_link_line($line_content_ref->{"text"}, $line_content_ref->{"url_num"}, $page_urls_ref);
        }
        elsif ($type eq "li")
        {
            ($rendered_ref, $num_words_in_lines_ref) = render_list_line($line_content_ref->{"text"});
        }
        elsif ($type eq "quote")
        {
            ($rendered_ref, $num_words_in_lines_ref) = render_quote_line($line_content_ref->{"text"});
        }
        elsif ($type eq "heading")
        {
            ($rendered_ref, $num_words_in_lines_ref) = render_heading_line($line_content_ref->{"text"}, $line_content_ref->{"level"});
        }
        
        push(@page_lines, @$rendered_ref);
        
        for my $word_count (@$num_words_in_lines_ref)
        {
            push(@num_words_before_line, $num_words_so_far);
            $num_words_so_far += $word_count;
        }
    }
    
    return (\@page_lines, \@num_words_before_line);
}

sub display_page #(page_lines, scroll_height)
{
    my $page_lines_ref = $_[0];
    my $scroll_height = $_[1];
    my $first_print = $_[2];
    
    my ($chars_wide, $chars_high, $pixels_wide, $pixels_high) = GetTerminalSize();
    
    if (not $first_print)
    {
        locate();
        cldown();
    }
    
    my $max_line_num = scalar(@$page_lines_ref) - 1;
    $scroll_height = max(min($scroll_height, $max_line_num - 1), 0);
    
    my $current_line_num = $scroll_height;
    my $lines_printed = 0;
    
    while ($current_line_num <= $max_line_num and $lines_printed < $chars_high)
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
    
    if ($first_print)
    {
        savepos();
        while ($lines_printed < $chars_high - 1)
        {
            print("\n");
            $lines_printed++;
        }
        loadpos();
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
    if (scalar(@_) > 0)
    {
        set_command_prompt($_[0]);
    }
    
    if ($current_command_error ne "")
    {
        locate(3, 1);
        clline();
        print("Error: $current_command_error");
        
        locate(4, 1);
        clline();
    }
    
    if ($current_command_prompt ne "")
    {
        locate(1, 1);
        clline();
        
        if ($current_command_error eq "")
        {
            locate(3, 1);
            clline();
        }
        
        locate(2, 1);
        clline();
        print("$current_command_prompt: ");
    }
}

sub set_command_prompt
{
    $current_command_prompt = $_[0];
}

sub set_command_error
{
    $current_command_error = $_[0];
}

sub find_line_num_of_word_num # want to find the index of the closest value equal or below $val
{
    my $arr_ref = $_[0];
    my $val = $_[1];
    
    my $start = 0;
    my $end = scalar(@$arr_ref);
    while ($start <= $end)
    {
        my $index = int($start + ($end - $start) / 2);
        if ($$arr_ref[$index] < $val)
        {
            if ($index == scalar(@$arr_ref) - 1 or $$arr_ref[$index + 1] > $val)
            {
                return $index;
            }
            
            $start = $index + 1;
            next;
        }
        if ($$arr_ref[$index] > $val)
        {
            $end = $index - 1;
            next;
        }
        
        return $index;
    }
    
    # should never get here
    return -1;
}

1;
