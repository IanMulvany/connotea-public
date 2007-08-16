[% IF is_main %]<h1 class="pagetitle">[% sitename %] Browser Buttons</h1>[% END %]

<p>The browser buttons are the quickest and easiest way to save
something to [% sitename %].</p>

<p>To learn how to install the buttons, have a look at
the <a href="getting_started">getting started instructions</a>.</p>

<div class="importantsidenote">
  <h3>Note to Users Upgrading from Firefox 1.x to Firefox 2.0</h3>
  <p>Firefox 2.0 offers different default security settings than
  Firefox 1.x. In Firefox 2.0, popup windows cannot be brought to the
  top of the window stack by Javascript unless you enable this
  feature. If you would like your [% sitename %] bookmarklet window to
  be on top as it was before, please visit your Firefox options,
  Content tab, and click the Advanced button next to Enable
  Javascript, and ensure that &quot;Raise or lower windows&quot; is
  checked.</p>
</div>

<p>Here are some browser buttons (or 'bookmarklets') for posting to
[% sitename %] and viewing [% sitename %] comments.</p>

<h2 class="subtitle">Saving to [% sitename %]</h2>

<ul>
  <li>[% bookmarklet('add','popup') %]
    <p>This bookmarklet will bring up a new window containing
    the <a href="add">Add to [% sitename %] form</a> from any page on
    the Web. The form will be pre-populated with information about
    that page.  You can then add tags, a short description of the
    page, and an optional personal comment.  If you're browsing one of
    the <a href="[% location %]guide#autocollection">supported
    sites</a>, the bibliographic information for the article will also
    be shown and saved.</p>
  </li>
  <li>[% bookmarklet('add','direct') %]
    <p>Alternatively, this bookmarklet will open the form in your main
    browser window. After you've posted the link, [% sitename %] will
    automatically return you to the article.</p>
  </li>
</ul>
<h2 class="subtitle">Viewing [% sitename %] Comments</h2>
<ul>
  <li>[% bookmarklet('comments','popup') %]
    <p>This brings up a new window showing any comments that have been
    made on [% sitename %] about the article you are reading.</p>
  </li>
  <li>[% bookmarklet('comments','direct') %]
    <p>If you'd prefer for the comments to be displayed in your main
    browser window, use this instead.</p>
  </li>
</ul>

<h2 class="subtitle">Adding [% sitename %] Comments</h2>
<ul>
  <li>[% bookmarklet('addcomment','popup') %]
   <p>To add a comment to [% sitename %] about the paper you're
   reading, use this bookmarklet, which will bring up a new window
   containing the comment form.</p>
  </li>
  <li>[% bookmarklet('addcomment','direct') %]
    <p>As above, this is an alternative that displays the form in the
    main browser window.</p>
  </li>
</ul>
