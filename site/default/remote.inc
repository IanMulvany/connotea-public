<h1>Remote Javascript Facilities for [% sitename %]</h1>

<p>We offer some client-side Javascript functions prepackaged to
coordinate with [% sitename %].</p>

<h2>Showing [% sitename %] Articles on Your Web Site</h2>

<p>You can display [% sitename %] articles on your web site by using
our remote Javascript facility.</p>

<p>In the HTML &lt;head&gt; place the following HTML elements, replacing
<b><code>username</code></b> with your [% sitename %] username:</p>

<pre>
  &lt;script type="text/javascript" src="[% location %]remote.js"&gt;//&lt;/script&gt;
  &lt;script type="text/javascript" src="[% location %]jsw/user/username"&gt;//&lt;/script&gt;
</pre>

<p>In the HTML &lt;body&gt; place the following HTML element at the
position where you would like a list of articles:</p>

<pre>
  &lt;div id="[% symbolname %]" class="[% symbolname %]"&gt;&lt;/div&gt;
</pre>

<p>The script in the head will arrange for an event to be called when
the site is loaded that fills the div in the body with the
articles.</p>

<p>Instead of <code>/user/username</code> in the second script element
above, you can use other queries that yield articles, such as
<code>/tag/tagname</code>
or <code>/user/username/tag/tagname</code>.</p>

<h2>Placing to Add To [% sitename %] Links on Your Web Site</h2>

<p>You can include &quot;Add To [% sitename %]&quot; hyperlinks
on your web site by using our remote Javascript facility.</p>

<p>In the HTML &lt;head&gt; place the following HTML element:</p>

<pre>
  &lt;script type="text/javascript" src="[% location %]remote.js"&gt;//&lt;/script&gt;
</pre>

<p>In the HTML &lt;body&gt; place hyperlinks such as the following
where you like:</p>

<pre>
  &lt;a href="javascript:addTo[% codename %]()"&gt;Add To [% sitename %]&lt;/a&gt;
</pre>

<p>The <code>addTo[% codename %]</code> Javascript function can also
be used in <code>onclick</code> handlers. It optionally accepts a URL
parameter and a title parameter, although these will default to the
current page.</p>
