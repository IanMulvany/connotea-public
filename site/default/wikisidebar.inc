<div id="wikinav">
<h2 class="wikisidebarh2notfirst">Navigate</h2>
<ul>
  <li><a href="${location}wiki">Community Pages Home</a></li>
  <li><a href="${location}wiki/User:$username?">My Profile Page</a></li>
  <li><a href="${location}wiki/Generate:PageList?prefix=User">All User Profile Pages</a></li>
  <li><a href="${location}wiki/Generate:PageList?prefix=Tag">All Tag Pages</a></li>
  <li><a href="${location}wiki/Generate:PageList?prefix=Group">All Group Pages</a></li>
  <li><a href="${location}wiki/Generate:PageList">All Community Pages</a></li>
  <li><a href="${location}wiki/Generate:RecentChanges">Recently Changed Pages</a></li>

</ul>

<h2 class="wikisidebarh2notfirst">Help</h2>
<p><span class="wikidunno">?</span>
means that the link is for a Community Page that hasn't  been created yet.</p>
<p><span class="wikiparsefail">Some text highlighted in red</span> means that there's an error in the wiki page code near that text.  Feel free to correct it!</p>
<p>To create a new page, click on an existing link, or use the form below.</p>

<p>
<form action="${location}wiki" onsubmit="if(this.create.value.indexOf(' ') != -1) { alert('No spaces in page names, please! Hint: TryCamelCase'); return false; }; if (/^[a-z0-9]/.test(this.create.value)) { alert('The first character of your page name should be a capital letter.'); return false; }; return true;">
<input type="text" name="create" size="12" />
<input type="submit" value="Create" />
</form>
</p>

<p>Be sure to link to your new page from another page, so readers can find it!</p>
</div>
