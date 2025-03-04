# Shiny browser for Gemini Protocol
A bare-bones terminal browser for [Gemini protocol](https://geminiprotocol.net/) pages written in Perl as a reference to some Minecraft youtubers. What am I doing with my life...
![Screenshot from 2025-03-04 00-41-12](https://github.com/user-attachments/assets/61a9d064-6daa-45d7-a647-dc84f06f086c)

## Features
* Type the address of a page and then the content of the page is shown on the screen
* Navigate to links in the page by number
* Non-Gemini links prompt to open in other applications (xdg-open)
* Smooth scrolling
* Word wrapping
* Maximum page width with centering (configurable in GeminiPage.pm)

## Controls
* q - quit
* l - prompt to type the number of a link to navigate to
* g - prompt to type an address to navigate to
* Arrow keys, Home, End, PageUp, PageDown, <, > - scrolling

## Dependencies
* Written with Perl 5.36.0 (I don't know much about Perl but it seems very version dependent...)
* IO::Socket::SSL
* Term::ANSIScreen
* Term::RawInput
* Term::ReadKey
