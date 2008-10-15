// Add Form AutoComplete Functions
//
// Copyright 2008 Nature Publishing Group
// This program is free software; you can redistribute it and/or
// modify it under the terms of the GNU General Public License
// as published by the Free Software Foundation; either version 2
// of the License, or (at your option) any later version.

var usageBoxDone = 0;
var alphaBoxDone = 0;
var lastCaretPos = 0;
var potentials;
var preferByUsage = 0;

function addsuggestion(id, tag, clear) {
  var suggestions = document.getElementById(id);
  var anchor = document.createElement('a');
  anchor.setAttribute('class', 'add-form-tag-suggestion tag');
  anchor.setAttribute('className', 'add-form-tag-suggestion tag');  // IE needs it to be className
  anchor.setAttribute('href', 'javascript:addtag(\'' + tag.replace(/\'/g, "\\'") + '\', ' + clear + ')');
  anchor.appendChild(document.createTextNode(tag));
  suggestions.appendChild(anchor);
}

function addtag(tag, clear) {
  var tagsBox = document.getElementById('tagsbox');
  var tagstring = tagsBox.value;
  var tagparts = analyseTagString(tagstring, lastCaretPos);
  tagsBox.value = '';

  function append(t) {
    if (t.match(/\S[\s,]+\S/))
      t = '"'+t+'"';
    if (tagsBox.value == '')
      tagsBox.value += t;
    else
      tagsBox.value += ', ' + t;
  }
  var addedtag = false;
  for (var i=0; i < tagparts.length; i++) {
    var addme = tagparts[i].text;
    if (tagparts[i].currentlyediting == true) {
      addme = tag;
      addedtag = true;
    }
    append(addme);
  }
  if (!addedtag)
    append(tag);
  tagsBox.value += ' ';
  tagsBox.focus();
  lastCaretPos = getCaretPosition(tagsBox);
  if (clear)
    clearsuggestions();
}

function clearsuggestions() {
  var obj = document.getElementById('add-form-ac-results-suggest');
  while (obj.firstChild)
    obj.removeChild(obj.firstChild);
  disable('tbox-all-usage');
  disable('tbox-all-alpha');
  disable('tbox-suggest');
  enable('tbox-closed');
}

function showAllUsage() {
  clearsuggestions();
  if (!usageBoxDone) {
    var list = new Array();
    for (var tag in tags)
      list.push({ 'tag' : tag, 'uOrder' : tags[tag] });
    list.sort(usageorder);
    for(var i=0; i < list.length; i++)
      addsuggestion('add-form-ac-results-usage', list[i].tag, false);
    usageBoxDone = 1;
  }
  disable('tbox-closed');
  disable('tbox-all-alpha');
  disable('tbox-suggest');
  enable('tbox-all-usage');
  preferByUsage = 1;
}

function showAllAlpha() {
  clearsuggestions();
  if (!alphaBoxDone) {
    for (var tag in tags)
      addsuggestion('add-form-ac-results-alpha', tag, false);
    alphaBoxDone = 1;
  }
  disable('tbox-closed');
  disable('tbox-all-usage');
  disable('tbox-suggest');
  enable('tbox-all-alpha');
  preferByUsage = 0;
}

function showAllByPreference() {
  if (preferByUsage)
    showAllUsage();
  else
    showAllAlpha();
}

function clearall() {
  clearsuggestions();
  disable('tbox-all-usage');
  disable('tbox-all-alpha');
  disable('tbox-suggest');
  enable('tbox-closed');
}

function enable(id) {
  var el = document.getElementById(id);
  el.style.display = '';
}

function disable(id) {
  var el = document.getElementById(id);
  el.style.display = 'none';
}

function usageorder(a, b) {
  return a.uOrder - b.uOrder;
}

function analyseTagString(tagString, caretPos) {
  var tagParts = new Array();
  var all = tagString.split('');
  var len = all.length;
  var inTag = false;
  var inQuote = false;
  var inQuoteChar = null;
  var part = { text: '', currentlyediting: false };

  for (var i = 0; i < len; i++) {
    var c = all[i];
    if (c.match(/\s/)) {
      if (!inTag)
        continue;
      else if (inQuote) {
        part.text += c;
        continue;
      }
      else if (inTag) {
        tagParts.push(part);
        part = { text: '', currentlyediting: false };
        inTag = false;
        continue;
      }
    }
    else if (c == '"') {
      if (!inTag) {
        inTag = true;
        inQuote = true;
        inQuoteChar = '"';
        continue;
      }
      else if (inQuote && inQuoteChar == '"') {
        tagParts.push(part);
        part = { text: '', currentlyediting: false };
        inTag = false;
        inQuote = false;
        inQuoteChar = null;
        continue;
      }
    }
    else if (c == "'") {
      if (!inTag) {
        inTag = true;
        inQuote = true;
        inQuoteChar = "'";
        continue;
      }
      else if (inQuote && inQuoteChar == "'") {
        tagParts.push(part);
        part = { text: '', currentlyediting: false };
        inTag = false;
        inQuote = false;
        inQuoteChar = null;
        continue;
      }
    }
    else if (c == ',') {
      if (inQuote) {
        // noop
      }
      else if (inTag) {
        tagParts.push(part);
        part = { text: '', currentlyediting: false };
        inTag = false;
        continue;
      }
      else {
        continue;
      }
    }
    inTag = true;
    if (caretPos == (i + 1))
      part.currentlyediting = true;
    part.text += c;
  }

  if (part.text.length)
    tagParts.push(part);

  return tagParts;
}

function autocompletetags() {
  var tagsBox = document.getElementById('tagsbox');
  var tagstring = tagsBox.value;

  lastCaretPos = getCaretPosition(tagsBox);

  clearsuggestions();

  if (tagstring.length == 0)
    return;

  var tagparts = analyseTagString(tagstring, lastCaretPos);

  potentials = new Array();
  for (var i=0; i < tagparts.length; i++) {
    if (tagparts[i].currentlyediting != true)
      continue;
    var lctagpart = tagparts[i].text.toLowerCase();

    if (lctagpart == '')
      continue;

    for (var tag in tags) {
      var lctag = tag.toLowerCase();
      if (lctag.indexOf(lctagpart) == 0)
        potentials.push( { 'tag' : tag, 'uOrder' : tags[tag] } );
    }
  }
  
  if (potentials.length)
    showSuggestByPreference();
}

function showSuggestAlpha() {
  clearsuggestions();

  for (var i=0; i< potentials.length; i++)
    addsuggestion('add-form-ac-results-suggest', potentials[i].tag, true);

  disable('tbox-all-usage');
  disable('tbox-all-alpha');
  disable('tbox-closed');
  disable('slink-usage');
  enable('slink-alpha');
  enable('tbox-suggest');
  preferByUsage = 0;
}

function showSuggestUsage() {
  clearsuggestions();

  var alphaPotentials = potentials.slice(0, potentials.length);

  alphaPotentials.sort(usageorder);
  for (var i=0; i< potentials.length; i++)
    addsuggestion('add-form-ac-results-suggest', alphaPotentials[i].tag, true);

  disable('tbox-all-usage');
  disable('tbox-all-alpha');
  disable('tbox-closed');
  disable('slink-alpha');
  enable('slink-usage');
  enable('tbox-suggest');
  preferByUsage = 1;
}

function showSuggestByPreference() {
  if (preferByUsage)
    showSuggestUsage();
  else
    showSuggestAlpha();
}

function getCaretPosition(input) {
  var cPos;
  if (input.setSelectionRange)
    cPos = input.selectionStart;
  /*  One IE way  */
  else if (document.selection) {
    var range = document.selection.createRange();
    var maxMoveRight = range.move('character', 1000);
    cPos = input.value.length - maxMoveRight;
  }
  return cPos;
}

function fixsize() {
  window.resizeTo(rec_popup_width(), rec_popup_height());
}

function getWindowHeight() {
  var total = 0;
  if (document.selection)     // IE
    for (var el = document.body; el; el = el.offsetParent) {
      total += el.offsetHeight;
    }
  else
    total = window.outerHeight;
  return total;
}

function sizeCheck() {
  var windowHeight = getWindowHeight();
  var screenHeight = screen.availHeight;
  if (screenHeight > windowHeight)
    window.resizeBy(0, ((screenHeight - windowHeight) / 2));
}
