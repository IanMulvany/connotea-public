#!/usr/bin/perl

# Test script that compares wiki formatter input to known output.

use Test::More tests => 83;
use Test::Exception;
use strict;
use warnings;

BEGIN {
  use_ok('Bibliotech::Component::Wiki') or exit;
  use_ok('Bibliotech::Fake') or exit;
}

use CGI;

my $f = Bibliotech::Wiki::CGI::Formatter->new;
isa_ok($f, 'Bibliotech::Wiki::CGI::Formatter');
#$f->trace(1);  # spew debug output

my $bibliotech = Bibliotech::Fake->new;
$bibliotech->cgi(CGI->new);
my $command = $bibliotech->command;
$command->verb('GET');
$command->output('html');
$command->page('wiki');

$f->bibliotech($bibliotech);
$f->prefix('/wiki/');

# use this to force true/false on exists tests
$::EXISTS = 1;
$f->node_exists_callback(sub { $::EXISTS });

sub wformat {
  local $_ = $f->format(shift);
  s/<div class=\"wiki(?:start|end)display\"><\/div>\n//g;  # discount the automatic div's
  return $_;
}

is(wformat(<<'EOI'), <<'EOO', 'paragraph');
Hello, World.
EOI
<p>Hello, World.</p>
EOO

is(wformat(<<'EOI'), <<'EOO', 'paragraph with line break');
Book 1
Book 2
Book 3
EOI
<p>Book 1<br />Book 2<br />Book 3</p>
EOO

is(wformat(<<'EOI'), <<'EOO', 'paragraph with international telephone number');
The White House can be reached at +1 202-456-1414.
EOI
<p>The White House can be reached at +1 202-456-1414.</p>
EOO

is(wformat(<<'EOI'), <<'EOO', 'bold');
this is *bold text*.
EOI
<p>this is <b>bold text</b>.</p>
EOO

is(wformat(<<'EOI'), <<'EOO', 'italic');
this is ''italic text''.
EOI
<p>this is <i>italic text</i>.</p>
EOO

is(wformat(<<'EOI'), <<'EOO', 'bold italic');
this is *''bold italic text''*.
EOI
<p>this is <b><i>bold italic text</i></b>.</p>
EOO

is(wformat(<<'EOI'), <<'EOO', 'highlighted');
this is **highlighted text**.
EOI
<p>this is <span class="wikihighlight">highlighted text</span>.</p>
EOO

is(wformat(<<'EOI'), <<'EOO', 'highlighted + italics + bold');
this is **highlighted, with ''italics and *boldness* together'' here!**.
EOI
<p>this is <span class="wikihighlight">highlighted, with <i>italics and <b>boldness</b> together</i> here!</span>.</p>
EOO

$::EXISTS = 1;
is(wformat(<<'EOI'), <<'EOO', 'wikiword exists');
this is a TestWikiWord.
EOI
<p>this is a <a href="/wiki/TestWikiWord" class="wikilink wikiexist">TestWikiWord</a>.</p>
EOO

$::EXISTS = 0;
is(wformat(<<'EOI'), <<'EOO', 'wikiword not exists');
this is a TestWikiWord.
EOI
<p>this is a <a href="/wiki/TestWikiWord?action=edit" class="wikilink wikinotexist">TestWikiWord</a><span class="wikidunno">?</span>.</p>
EOO

$::EXISTS = 1;
is(wformat(<<'EOI'), <<'EOO', 'wikiword in brackets exists');
this is a [TestWikiWord].
EOI
<p>this is a <a href="/wiki/TestWikiWord" class="wikilink wikiexist">TestWikiWord</a>.</p>
EOO

$::EXISTS = 0;
is(wformat(<<'EOI'), <<'EOO', 'wikiword in brackets not exists');
this is a [TestWikiWord].
EOI
<p>this is a <a href="/wiki/TestWikiWord?action=edit" class="wikilink wikinotexist">TestWikiWord</a><span class="wikidunno">?</span>.</p>
EOO

$::EXISTS = 1;
is(wformat(<<'EOI'), <<'EOO', 'wikiword with alternate text exists');
this is a [TestWikiWord|curiosity].
EOI
<p>this is a <a href="/wiki/TestWikiWord">curiosity</a>.</p>
EOO

$::EXISTS = 0;
is(wformat(<<'EOI'), <<'EOO', 'wikiword with alternate text not exists');
this is a [TestWikiWord|curiosity].
EOI
<p>this is a <a href="/wiki/TestWikiWord">curiosity</a>.</p>
EOO

is(wformat(<<'EOI'), <<'EOO', 'explicit_link');
this is a link to [http://www.nature.com/|Nature].
EOI
<p>this is a link to <a href="http://www.nature.com/">Nature</a>.</p>
EOO

is(wformat(<<'EOI'), <<'EOO', 'explicit_link with bold');
this is a link to [http://www.nature.com/|*Nature*].
EOI
<p>this is a link to <a href="http://www.nature.com/"><b>Nature</b></a>.</p>
EOO

is(wformat(<<'EOI'), <<'EOO', 'explicit_link with double brackets and extra space');
this is a link to [[http://www.nature.com/|Nature ]].
EOI
<p>this is a link to <a href="http://www.nature.com/">Nature </a>.</p>
EOO

is(wformat(<<'EOI'), <<'EOO', 'explicit_link with double brackets and mailto scheme');
this is a link to [[mailto:connotea@nature.com|customer service]].
EOI
<p>this is a link to <a href="mailto:connotea@nature.com">customer service</a>.</p>
EOO

$::EXISTS = 1;
is(wformat(<<'EOI'), <<'EOO', 'wikilink exists');
wikilink=TestWikiWord=
EOI
<p><a href="/wiki/TestWikiWord" class="wikilink wikiexist">TestWikiWord</a></p>
EOO

$::EXISTS = 0;
is(wformat(<<'EOI'), <<'EOO', 'wikilink not exists');
wikilink=TestWikiWord=
EOI
<p><a href="/wiki/TestWikiWord?action=edit" class="wikilink wikinotexist">TestWikiWord</a><span class="wikidunno">?</span></p>
EOO

$::EXISTS = 1;
is(wformat(<<'EOI'), <<'EOO', 'wikilink with version exists');
wikilink=TestWikiWord#3=
EOI
<p><a href="/wiki/TestWikiWord?version=3" class="wikilink wikiexist">TestWikiWord #3</a></p>
EOO

$::EXISTS = 0;
is(wformat(<<'EOI'), <<'EOO', 'wikilink with version not exists');
wikilink=TestWikiWord#3=
EOI
<p><a href="/wiki/TestWikiWord?action=edit" class="wikilink wikinotexist">TestWikiWord</a><span class="wikidunno">?</span></p>
EOO

$::EXISTS = 1;
is(wformat(<<'EOI'), <<'EOO', 'wikilink with version and base exists');
wikilink=TestWikiWord#3##2=
EOI
<p><a href="/wiki/TestWikiWord?action=diff&amp;base=2&amp;version=3" class="wikilink wikiexist">TestWikiWord #2 - #3</a></p>
EOO

$::EXISTS = 0;
is(wformat(<<'EOI'), <<'EOO', 'wikilink with version and base not exists');
wikilink=TestWikiWord#3##2=
EOI
<p><a href="/wiki/TestWikiWord?action=edit" class="wikilink wikinotexist">TestWikiWord</a><span class="wikidunno">?</span></p>
EOO

$::EXISTS = 1;
is(wformat(<<'EOI'), <<'EOO', 'wikilink with text exists');
wikilink=TestWikiWord="a test page"
EOI
<p><a href="/wiki/TestWikiWord" class="wikilink wikiexist">a test page</a></p>
EOO

$::EXISTS = 0;
is(wformat(<<'EOI'), <<'EOO', 'wikilink with text not exists');
wikilink=TestWikiWord="a test page"
EOI
<p><a href="/wiki/TestWikiWord?action=edit" class="wikilink wikinotexist">a test page</a><span class="wikidunno">?</span></p>
EOO

$::EXISTS = 1;
is(wformat(<<'EOI'), <<'EOO', 'wikilink with version and text exists');
wikilink=TestWikiWord#3="a test page"
EOI
<p><a href="/wiki/TestWikiWord?version=3" class="wikilink wikiexist">a test page</a></p>
EOO

$::EXISTS = 0;
is(wformat(<<'EOI'), <<'EOO', 'wikilink with version and text not exists');
wikilink=TestWikiWord#3="a test page"
EOI
<p><a href="/wiki/TestWikiWord?action=edit" class="wikilink wikinotexist">a test page</a><span class="wikidunno">?</span></p>
EOO

$::EXISTS = 1;
is(wformat(<<'EOI'), <<'EOO', 'wikilink with version and base and text exists');
wikilink=TestWikiWord#3##2="a test page"
EOI
<p><a href="/wiki/TestWikiWord?action=diff&amp;base=2&amp;version=3" class="wikilink wikiexist">a test page</a></p>
EOO

$::EXISTS = 0;
is(wformat(<<'EOI'), <<'EOO', 'wikilink with version and base and text not exists');
wikilink=TestWikiWord#3##2="a test page"
EOI
<p><a href="/wiki/TestWikiWord?action=edit" class="wikilink wikinotexist">a test page</a><span class="wikidunno">?</span></p>
EOO

is(wformat(<<'EOI'), <<'EOO', 'heading level 1');
= My Heading =
EOI
<a name="hn0"></a><h1>My Heading</h1>
EOO

is(wformat(<<'EOI'), <<'EOO', 'heading level 2');
== My Heading ==
EOI
<a name="hn0"></a><h2>My Heading</h2>
EOO

is(wformat(<<'EOI'), <<'EOO', 'heading level 3');
=== My Heading ===
EOI
<a name="hn0"></a><h3>My Heading</h3>
EOO

is(wformat(<<'EOI'), <<'EOO', 'heading level 4');
==== My Heading ====
EOI
<a name="hn0"></a><h4>My Heading</h4>
EOO

is(wformat(<<'EOI'), <<'EOO', 'heading with equals');
= My Key=Value Heading =
EOI
<a name="hn0"></a><h1>My Key=Value Heading</h1>
EOO

is(wformat(<<'EOI'), <<'EOO', 'heading with bold and italic');
= This *Great* Heading Must ''Pass'' Without Trouble =
EOI
<a name="hn0"></a><h1>This <b>Great</b> Heading Must <i>Pass</i> Without Trouble</h1>
EOO

$::EXISTS = 1;
is(wformat(<<'EOI'), <<'EOO', 'heading just wikiword exists');
= TestWikiWord =
EOI
<a name="hn0"></a><h1><a href="/wiki/TestWikiWord" class="wikilink wikiexist">TestWikiWord</a></h1>
EOO

$::EXISTS = 0;
is(wformat(<<'EOI'), <<'EOO', 'heading just wikiword not exists');
= TestWikiWord =
EOI
<a name="hn0"></a><h1><a href="/wiki/TestWikiWord?action=edit" class="wikilink wikinotexist">TestWikiWord</a><span class="wikidunno">?</span></h1>
EOO

is(wformat(<<'EOI'), <<'EOO', 'heading followed by blank line');
= People =

EOI
<a name="hn0"></a><h1>People</h1>
EOO

is(wformat(<<'EOI'), <<'EOO', 'heading with acronym followed by blank line');
= People from Integragen SA =

EOI
<a name="hn0"></a><h1>People from Integragen SA</h1>
EOO

$::EXISTS = 1;
is(wformat(<<'EOI'), <<'EOO', 'heading with two wikiwords exists');
= The TestWikiWord page has all the PerlProgramming that you need =
EOI
<a name="hn0"></a><h1>The <a href="/wiki/TestWikiWord" class="wikilink wikiexist">TestWikiWord</a> page has all the <a href="/wiki/PerlProgramming" class="wikilink wikiexist">PerlProgramming</a> that you need</h1>
EOO

$::EXISTS = 0;
is(wformat(<<'EOI'), <<'EOO', 'heading with two wikiwords not exists');
= The TestWikiWord page has all the PerlProgramming that you need =
EOI
<a name="hn0"></a><h1>The <a href="/wiki/TestWikiWord?action=edit" class="wikilink wikinotexist">TestWikiWord</a><span class="wikidunno">?</span> page has all the <a href="/wiki/PerlProgramming?action=edit" class="wikilink wikinotexist">PerlProgramming</a><span class="wikidunno">?</span> that you need</h1>
EOO

is(wformat(<<'EOI'), <<'EOO', 'heading with extra spacing and explicit_link with double brackets');
==  Welcome to [[http://www.connotea.org/wiki/User:msredsonyas|MsRedSonyas ]]  Boogie Woogie Wiki Disaster Board   ==
EOI
<a name="hn0"></a><h2>Welcome to <a href="http://www.connotea.org/wiki/User:msredsonyas">MsRedSonyas </a>  Boogie Woogie Wiki Disaster Board</h2>
EOO

is(wformat(<<'EOI'), <<'EOO', 'rss link macro');
{>RSS}
EOI
<p><a href="http://localhost/rss/wiki/" class="rsslinkright"><img src="http://localhost/rss_button.gif" border="0" /></a></p>
EOO

is(wformat(<<'EOI'), <<'EOO', 'tall div macro');
{^100}
EOI
<p><div style="height: 100px"></div></p>
EOO

is(wformat(<<'EOI'), <<'EOO', 'local image');
/connotea_logo.gif
EOI
<p><img src="/connotea_logo.gif" border="0" /></p>
EOO

is(wformat(<<'EOI'), <<'EOO', 'local image with style');
/connotea_logo.gif (style="float: right")
EOI
<p><img style="float: right" src="/connotea_logo.gif" border="0" /></p>
EOO

is(wformat(<<'EOI'), <<'EOO', 'rule');
----
EOI
<hr />
EOO

is(wformat(<<'EOI'), <<'EOO', 'quote');
    God save the Queen.
EOI
<pre><code>God save the Queen.</code></pre>
EOO

$::EXISTS = 1;
is(wformat(<<'EOI'), <<'EOO', 'quote with wikiword does not encode');
    God save TheQueen.
EOI
<pre><code>God save TheQueen.</code></pre>
EOO

is(wformat(<<'EOI'), <<'EOO', 'quote with arithmetic does not encode');
    5=2*2+1
EOI
<pre><code>5=2*2+1</code></pre>
EOO

is(wformat(<<'EOI'), <<'EOO', 'quote using perl');
    #!/usr/bin/perl
    use strict;
    use warnings;
    
    print "Hello, World.\n";
    foreach (1..10) {
      print "$_\n";
    }
    
    exit 1;
EOI
<pre><code>#!/usr/bin/perl
use strict;
use warnings;

print &quot;Hello, World.\n&quot;;
foreach (1..10) {
  print &quot;$_\n&quot;;
}

exit 1;</code></pre>
EOO

is(wformat(<<'EOI'), <<'EOO', 'quote that looks like a heading');
    = A Fake Heading =
EOI
<pre><code>= A Fake Heading =</code></pre>
EOO

is(wformat(<<'EOI'), <<'EOO', 'bullet_list');
    * First List Item
    * Second List Item
    * Third List Item
EOI
<ul>
<li>First List Item</li>
<li>Second List Item</li>
<li>Third List Item</li>
</ul>
EOO

is(wformat(<<'EOI'), <<'EOO', 'bullet_list with nesting and bold');
    * First *List* Item
     * Sub-1
     * *Sub-2*
    * Second List Item
    * Third List Item
EOI
<ul>
<li>First <b>List</b> Item</li>
<ul>
<li>Sub-1</li>
<li><b>Sub-2</b></li>
</ul>
<li>Second List Item</li>
<li>Third List Item</li>
</ul>
EOO

is(wformat(<<'EOI'), <<'EOO', 'number_list');
    #. First List Item
    #. Second List Item
    #. Third List Item
EOI
<ol>
<li>First List Item</li>
<li>Second List Item</li>
<li>Third List Item</li>
</ol>
EOO

is(wformat(<<'EOI'), <<'EOO', 'number_list with nesting and bold');
    #. First *List* Item
     #. Sub-1
     #. *Sub-2*
    #. Second List Item
    #. Third List Item
EOI
<ol>
<li>First <b>List</b> Item</li>
<ol>
<li>Sub-1</li>
<li><b>Sub-2</b></li>
</ol>
<li>Second List Item</li>
<li>Third List Item</li>
</ol>
EOO

is(wformat(<<'EOI'), <<'EOO', 'quote/bullet_list/number_list rapid switching');
    this is a quote

    * this is a bullet
    #. this is a number
    this is a quote

    * this is a bullet
    #. this is a number
EOI
<pre><code>this is a quote</code></pre>
<ul>
<li>this is a bullet</li>
</ul>
<ol>
<li>this is a number</li>
</ol>
<pre><code>this is a quote</code></pre>
<ul>
<li>this is a bullet</li>
</ul>
<ol>
<li>this is a number</li>
</ol>
EOO

is(wformat(<<'EOI'), <<'EOO', 'table');
| *Name*   |  *Score* |
| Bobby    |      1.0 |
| Sally    |      2.5 |
| Jeff     |      3.2 |
| End ||
EOI
<table class="wikitable"><tr class="wikitablerow wikitableoddrow"><th align="left" class="wikitablecell">Name</th> <th align="right" class="wikitablecell">Score</th></tr> <tr class="wikitablerow wikitableevenrow"><td align="left" class="wikitablecell">Bobby</td> <td align="right" class="wikitablecell">1.0</td></tr> <tr class="wikitablerow wikitableoddrow"><td align="left" class="wikitablecell">Sally</td> <td align="right" class="wikitablecell">2.5</td></tr> <tr class="wikitablerow wikitableevenrow"><td align="left" class="wikitablecell">Jeff</td> <td align="right" class="wikitablecell">3.2</td></tr> <tr class="wikitablerow wikitableoddrow"><td align="center" colspan="2" class="wikitablecell">End</td></tr></table>
EOO

is(wformat(<<'EOI'), <<'EOO', 'heading, paragraph, rule');
= Welcome =

I want to own an ice cream factory.

----
EOI
<a name="hn0"></a><h1>Welcome</h1>
<p>I want to own an ice cream factory.</p>
<hr />
EOO

is(wformat(<<'EOI'), <<'EOO', 'equals in paragraph');
The body of the POST should be simply an HTML form-style set of key=value URL-escaped pairs.
EOI
<p>The body of the POST should be simply an HTML form-style set of key=value URL-escaped pairs.</p>
EOO

is(wformat(<<'EOI'), <<'EOO', 'italics on URL followed by highlight');
Or to get all the tags used on ''http://www.google.com/'', **GET** the following:
EOI
<p>Or to get all the tags used on <i>http://www.google.com/</i>, <span class="wikihighlight">GET</span> the following:</p>
EOO

$::EXISTS = 1;
is(wformat(<<'EOI'), <<'EOO', 'example recent changes lines');
= Recent Changes =
    * wikilink=Sandbox#31= (wikilink=Sandbox#31##30="diff from last" | wikilink=Sandbox##31="diff to current") edited by User:martin
    * wikilink=Tag:evolution#6= (wikilink=Tag:evolution#6##5="diff from last" | wikilink=Tag:evolution##6="diff to current") edited by User:martin
EOI
<a name="hn0"></a><h1>Recent Changes</h1>
<ul>
<li><a href="/wiki/Sandbox?version=31" class="wikilink wikiexist">Sandbox #31</a> (<a href="/wiki/Sandbox?action=diff&amp;base=30&amp;version=31" class="wikilink wikiexist">diff from last</a> | <a href="/wiki/Sandbox?action=diff&amp;base=31" class="wikilink wikiexist">diff to current</a>) edited by <a href="/wiki/User:martin" class="wikilink wikiexist">User:martin</a></li>
<li><a href="/wiki/Tag:evolution?version=6" class="wikilink wikiexist">Tag:evolution #6</a> (<a href="/wiki/Tag:evolution?action=diff&amp;base=5&amp;version=6" class="wikilink wikiexist">diff from last</a> | <a href="/wiki/Tag:evolution?action=diff&amp;base=6" class="wikilink wikiexist">diff to current</a>) edited by <a href="/wiki/User:martin" class="wikilink wikiexist">User:martin</a></li>
</ul>
EOO

is(wformat(<<'EOI'), <<'EOO', 'mixed and nested lists');
    1. First
    2. Second
     a. Inner 1
     a. Inner 2
    2. Repeat #2
    3. Now Go To 3
     i. Some Point
     i. Some Other Point
EOI
<ol>
<li value="1">First</li>
<li value="2">Second</li>
<ol>
<li type="a">Inner 1</li>
<li type="a">Inner 2</li>
</ol>
<li value="2">Repeat #2</li>
<li value="3">Now Go To 3</li>
<ol>
<li type="i">Some Point</li>
<li type="i">Some Other Point</li>
</ol>
</ol>
EOO

is(wformat(<<'EOI'), <<'EOO', 'heading and bullet_list with explicit_link\'s');
== Interests ==
    * [http://www.connotea.org/user/lindenb/tag/bioinformatics|bioinformatics]
    * [http://www.connotea.org/user/lindenb/tag/semantic web|semantic web]
    * [http://www.connotea.org/user/lindenb/tag/social networks|social networks]
    * [http://www.connotea.org/user/lindenb/tag/comics|comics]
EOI
<a name="hn0"></a><h2>Interests</h2>
<ul>
<li><a href="http://www.connotea.org/user/lindenb/tag/bioinformatics">bioinformatics</a></li>
<li><a href="http://www.connotea.org/user/lindenb/tag/semantic web">semantic web</a></li>
<li><a href="http://www.connotea.org/user/lindenb/tag/social networks">social networks</a></li>
<li><a href="http://www.connotea.org/user/lindenb/tag/comics">comics</a></li>
</ul>
EOO

$::EXISTS = 1;
is(wformat(<<'EOI'), <<'EOO', 'connotea wiki home text');
= The Connotea Community Pages =

Welcome to the Connotea Community Pages, where [http://www.connotea.org|Connotea] users can read, write and edit articles about all aspects of Connotea. 

Here you\'ll find articles about [CommunityArticles|how to use the site], a community-written wikilink=FAQ=, a list of [RequestedFeatures|requested features] and [PossibleProblems|possible problems], and more. Because the Community Pages are a [http://en.wikipedia.org/wiki/Wiki|wiki], any Connotea user can start new pages or edit existing ones, so you can talk about anything you like to do with Connotea.

In addition, each Connotea user has their own [Generate:PageList?prefix=User|Profile Page], where they can give as much or as little information about themselves and their collections as they like. You can also set up dedicated pages for your [Generate:PageList?prefix=Group|groups], and even create pages about [Generate:PageList?prefix=Tag|Connotea tags]. 

To get started here, take a look around and start your own page or contribute to an existing one. If you would prefer to practice editing before you work on a real page, you can try it out in the [SandBox|sandbox]. When you edit a page, you will see more information on how to format text, and if you need any more information, see the [WikiHelp|help pages]. Any problems, ask other users on these pages or email us at [mailto:connotea@nature.com|connotea@nature.com] 

Subscribe to the [http://www.connotea.org/rss/wiki | RSS feed] of recently changed pages.
EOI
<a name="hn0"></a><h1>The Connotea Community Pages</h1>
<p>Welcome to the Connotea Community Pages, where <a href="http://www.connotea.org">Connotea</a> users can read, write and edit articles about all aspects of Connotea.</p>
<p>Here you\&#39;ll find articles about <a href="/wiki/CommunityArticles">how to use the site</a>, a community-written <a href="/wiki/FAQ" class="wikilink wikiexist">FAQ</a>, a list of <a href="/wiki/RequestedFeatures">requested features</a> and <a href="/wiki/PossibleProblems">possible problems</a>, and more. Because the Community Pages are a <a href="http://en.wikipedia.org/wiki/Wiki">wiki</a>, any Connotea user can start new pages or edit existing ones, so you can talk about anything you like to do with Connotea.</p>
<p>In addition, each Connotea user has their own <a href="/wiki/Generate:PageList?prefix=User">Profile Page</a>, where they can give as much or as little information about themselves and their collections as they like. You can also set up dedicated pages for your <a href="/wiki/Generate:PageList?prefix=Group">groups</a>, and even create pages about <a href="/wiki/Generate:PageList?prefix=Tag">Connotea tags</a>.</p>
<p>To get started here, take a look around and start your own page or contribute to an existing one. If you would prefer to practice editing before you work on a real page, you can try it out in the <a href="/wiki/SandBox">sandbox</a>. When you edit a page, you will see more information on how to format text, and if you need any more information, see the <a href="/wiki/WikiHelp">help pages</a>. Any problems, ask other users on these pages or email us at <a href="mailto:connotea@nature.com">connotea@nature.com</a></p>
<p>Subscribe to the <a href="http://www.connotea.org/rss/wiki">RSS feed</a> of recently changed pages.</p>
EOO

is(wformat(<<'EOI'), <<'EOO', 'escaped bold');
this is \*not bold\*.
EOI
<p>this is *not bold*.</p>
EOO

is(wformat(<<'EOI'), <<'EOO', 'escaped italic');
this is \''not italic\''.
EOI
<p>this is &#39;&#39;not italic&#39;&#39;.</p>
EOO

is(wformat(<<'EOI'), <<'EOO', 'escaped user entity link');
use \@>User(ben) to link to ben's page.
EOI
<p>use @&gt;User(ben) to link to ben&#39;s page.</p>
EOO

is(wformat(<<'EOI'), <<'EOO', 'escaped bold italic');
this is \*not bold and \''italic\''\* for heaven's sake.
EOI
<p>this is *not bold and &#39;&#39;italic&#39;&#39;* for heaven&#39;s sake.</p>
EOO

$::EXISTS = 1;
is(wformat(<<'EOI'), <<'EOO', 'escaped wikiword');
the page \TestWikiWord will be seen but not linked.
EOI
<p>the page TestWikiWord will be seen but not linked.</p>
EOO

$::EXISTS = 1;
is(wformat(<<'EOI'), <<'EOO', 'escaped user prefixed wikiword');
the page \User:martin will be seen but not linked.
EOI
<p>the page User:martin will be seen but not linked.</p>
EOO

$::EXISTS = 1;
is(wformat(<<'EOI'), <<'EOO', 'escaped backslash before wikiword');
the page \\TestWikiWord will be seen with a single backslash and linked.
EOI
<p>the page \<a href="/wiki/TestWikiWord" class="wikilink wikiexist">TestWikiWord</a> will be seen with a single backslash and linked.</p>
EOO

is(wformat(<<'EOI'), <<'EOO', 'backslashes in path');
look at C:\DOS\AUTOEXEC.BAT
EOI
<p>look at C:\DOS\AUTOEXEC.BAT</p>
EOO

is(wformat(<<'EOI'), <<'EOO', 'literal macro with wikiword');
this is {LITERAL:TestWikiWord}.
EOI
<p>this is TestWikiWord.</p>
EOO

is(wformat(<<'EOI'), <<'EOO', 'literal macro with escaped brace');
this is a brace: {LITERAL:\}}
EOI
<p>this is a brace: }</p>
EOO

is(wformat(<<'EOI'), <<'EOO', 'literal macro with an html tag fails');
a {LITERAL:<b>} tag in html makes text bold.
EOI
<p class="wikiparsefail"><!-- parser failed: -->a {LITERAL:&lt;b&gt;} tag in html makes text bold.<!-- end --></p>
EOO

is(wformat(<<'EOI'), <<'EOO', 'plain macro with an html tag');
a {PLAIN:<b>} tag in html makes text bold.
EOI
<p>a &lt;b&gt; tag in html makes text bold.</p>
EOO

is(wformat(<<'EOI'), <<'EOO', 'explicit_link with prefixed wikiword with spaces but no quotes');
[Tag:genomic islands|genomic islands]
EOI
<p><a href="/wiki/Tag:genomic islands">genomic islands</a></p>
EOO

is(wformat(<<'EOI'), <<'EOO', 'connotea user morgan\'s wiki page');
I am a PhD student of the [http://bioinformatics.bcgsc.ca/|Bioinformatics Training Program] in Vancouver, British Columbia, Canada. My current research is focused on identification and characterization of [Tag:genomic islands|genomic islands] in bacteria using comparative genomics. I am a member of the Connotea [Group:Bioinformatics Training Program|Bioinformatics Training Program] group.
EOI
<p>I am a PhD student of the <a href="http://bioinformatics.bcgsc.ca/">Bioinformatics Training Program</a> in Vancouver, British Columbia, Canada. My current research is focused on identification and characterization of <a href="/wiki/Tag:genomic islands">genomic islands</a> in bacteria using comparative genomics. I am a member of the Connotea <a href="/wiki/Group:Bioinformatics Training Program">Bioinformatics Training Program</a> group.</p>
EOO
