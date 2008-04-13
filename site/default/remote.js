// public function, designed to be called from third party web pages
function addTo[% codename %] (url, title) {
  if (url == undefined) url = window.location;
  var w = open(bibliotech_location() + 'addpopup?continue=confirm&uri=' + window.encodeURIComponent(url) + (title ? '&usertitle=' + window.encodeURIComponent(title) : ''), 'add', 'width=720,height=755,scrollbars,resizable');
  void(window.setTimeout('w.focus()', 200));
}

// public function, designed to be called from third party web pages
function showFrom[% codename %] (path, num) {
  if (num == undefined) num = 10;
  void(bibliotech_loadXMLDoc(bibliotech_location() + 'rss' + path + (num != 10 ? '?num=' + num : '')));
}

function bibliotech_location () {
  return '[% location %]';
}

function bibliotech_reqObj () {
  if (window.XMLHttpRequest) {
    return new XMLHttpRequest();
  } else if (window.ActiveXObject) {
    return new ActiveXObject("Microsoft.XMLHTTP");
  }
}

function bibliotech_loadXMLDoc (url)  {
  var req = bibliotech_reqObj();
  if (req) {
    req.onreadystatechange = function () { bibliotech_processReqChange(req); }
    req.open("GET", url, true);
    req.send(null);
  } else {
    alert("Unable to use AJAX in this browser.");
  }
}

function bibliotech_processReqChange (req) {
  if (req.readyState == 4) {
    if (req.status == 200) {
      bibliotech_processXML(req.responseXML.documentElement);
    } else {
      alert("There was a problem retrieving the XML data:\n" + req.statusText);
    }
  }
}

function bibliotech_processXML (res) {
  var channel = bibliotech_getChannel(res);
  var items   = bibliotech_getItems(res);
  var div     = bibliotech_getDisplayNode();
  bibliotech_clearDiv(div);
  bibliotech_updateDiv(div, channel, items, false);
}

function bibliotech_showLoaded (channel, items) {
  var div = bibliotech_getDisplayNode();
  bibliotech_clearDiv(div);
  bibliotech_updateDiv(div, channel, items, true);
}

function bibliotech_getChannel (res) {
  var link  = res.getElementsByTagName('link')[0].firstChild.nodeValue;
  var title = res.getElementsByTagName('title')[0].firstChild.nodeValue;
  return {link : link, title : title};
}

function bibliotech_getItems (res) {
  var itemNodes = res.getElementsByTagName('item');
  var items = new Array();
  for (var i = 0; i < itemNodes.length; i++) {
    items.push(bibliotech_getItem(itemNodes[i]));
  }
  return items;
}

function bibliotech_getItem (itemNode) {
  var uri      = itemNode.getElementsByTagName('uri')[0].getElementsByTagName('URI')[0].getAttribute('rdf:about');
  var link     = itemNode.getElementsByTagName('link')[0].firstChild.nodeValue;
  var title    = itemNode.getElementsByTagName('title')[0].firstChild.nodeValue;
  var tagNodes = itemNode.getElementsByTagName('subject');
  var tags = new Array();
  for (var t = 0; t < tagNodes.length; t++) {
    var tagname = tagNodes[t].firstChild.nodeValue;
    tags.push(tagname);
  }
  return {uri : uri, link : link, title : title, tags : tags};
}

function bibliotech_getDisplayNode () {
  return document.getElementById('[% symbolname %]');
}

function bibliotech_tagUrl (tagname) {
  return bibliotech_location() + 'tag/' + tagname;
}

function bibliotech_sayLoading (div) {
  div.removeChild(div.firstChild);
  div.appendChild(document.createTextNode('Loading...'));
}

function bibliotech_clearDiv (div) {
  while (div.childNodes.length > 0) {
    div.removeChild(div.firstChild);
  }
}

function bibliotech_createHeadNode (channel, cssIdClass) {
  var headNode = document.createElement('div');
  headNode.setAttribute('id', cssIdClass);
  headNode.setAttribute('class', cssIdClass);
  var a = document.createElement('a');
  a.setAttribute('href', channel.link);
  a.setAttribute('title', channel.title);
  a.appendChild(document.createTextNode(channel.title));
  headNode.appendChild(a);
  return headNode;
}

function bibliotech_createItemsNode (items, listCssIdClass, singleCssClass, infoCssClass, tagListCssClass, tagCssClass, headCssId, hrefNormal) {
  var itemsNode = document.createElement('ul');
  itemsNode.setAttribute('id', listCssIdClass);
  itemsNode.setAttribute('class', listCssIdClass);
  for (var i = 0; i < items.length; i++) {
      itemsNode.appendChild(bibliotech_createItemNode(items[i], singleCssClass, infoCssClass, tagListCssClass, tagCssClass, headCssId, hrefNormal));
  }
  return itemsNode;
}

function bibliotech_createItemNode (item, cssClass, infoCssClass, tagListCssClass, tagCssClass, headCssId, hrefNormal) {
  var itemNode = document.createElement('li');
  itemNode.setAttribute('class', cssClass);
  var a = document.createElement('a');
  a.setAttribute('href', item.uri);
  a.setAttribute('title', item.title);
  a.appendChild(document.createTextNode(item.title));
  itemNode.appendChild(a);
  itemNode.appendChild(document.createTextNode(' '));
  itemNode.appendChild(bibliotech_createItemInfoNode(item, infoCssClass));
  itemNode.appendChild(document.createTextNode(' '));
  itemNode.appendChild(bibliotech_createItemTagsNode(item.tags, tagListCssClass, tagCssClass, headCssId, hrefNormal));
  return itemNode;
}

function bibliotech_createItemInfoNode (item, cssClass) {
  var infoNode = document.createElement('span');
  infoNode.setAttribute('class', cssClass);
  var a = document.createElement('a');
  a.setAttribute('href', item.link);
  a.setAttribute('title', item.title);
  a.appendChild(document.createTextNode('info'));
  infoNode.appendChild(document.createTextNode('('));
  infoNode.appendChild(a);
  infoNode.appendChild(document.createTextNode(')'));
  return infoNode;
}

function bibliotech_createItemTagsNode (tags, cssClass, tagCssClass, headCssId, hrefNormal) {
  var tagListNode = document.createElement('span');
  tagListNode.setAttribute('class', cssClass);
  tagListNode.appendChild(document.createTextNode('['));
  for (var t = 0; t < tags.length; t++) {
    if (t > 0) tagListNode.appendChild(document.createTextNode(' '));
    tagListNode.appendChild(bibliotech_createItemTagNode(tags[t], tagCssClass, headCssId, hrefNormal));
  }
  tagListNode.appendChild(document.createTextNode(']'));
  return tagListNode;
}

function bibliotech_createItemTagNode (tag, cssClass, headCssId, hrefNormal) {
  var tagNode = document.createElement('a');
  tagNode.setAttribute('class', cssClass);
  if (hrefNormal) {
    tagNode.setAttribute('href', bibliotech_tagUrl(tag));
  } else {
    tagNode.setAttribute('href', '#');
    tagNode.setAttribute('onclick', 'bibliotech_sayLoading(document.getElementById(\'' + headCssId + '\')); ' +
			            'showFrom[% codename %](\'/tag/' + tag + '\')');
  }
  tagNode.setAttribute('title', 'Tag: ' + tag);
  tagNode.appendChild(document.createTextNode(tag));
  return tagNode;
}

function bibliotech_updateDiv (div, channel, items, hrefNormal) {
  var id = div.getAttribute('id');
  div.appendChild(bibliotech_createHeadNode(channel, id + '_head'));
  div.appendChild(bibliotech_createItemsNode(items, id + '_items', id + '_item', id + '_info', id + '_tags', id + '_tag', id + '_head', hrefNormal));
}

function bibliotech_addLoadEvent (func) {
  if (document.addEventListener) {
    document.addEventListener('DOMContentLoaded', func, false);
  } else {
    document.onreadystatechange = function () {
      if (document.readyState == 'interactive') {
	func();
      }
    };
  }
}
