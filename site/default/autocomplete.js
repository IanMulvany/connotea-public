var reportWindow;
var usageBoxDone = 0;
var alphaBoxDone = 0;
var lastCaretPos = 0;
var potentials;
var preferByUsage = 0;

function addsuggestion(id, tag, clear) {
  document.getElementById(id).innerHTML += '<a class="add-form-tag-suggestion tag" href="javascript:addtag(\'' + tag.replace(/\'/g, "\\'") + '\', ' + clear + ')">' + tag + '</a>';
}

function addtag(tag, clear) {
  report("LCP: " + lastCaretPos);
  var tagsBox = document.getElementById('tagsbox');
  var tagstring = tagsBox.value;
  var tagparts = analyseTagString(tagstring, lastCaretPos);
  tagsBox.value = '';

  function append(t) {
    if(t.match(/\S[\s,]+\S/)) {
      t = '"'+t+'"';
     } 
    if(tagsBox.value == '') {
      tagsBox.value += t;
    }
    else {
      tagsBox.value += ', ' + t;
    }
  }
  var addedtag = false;
  for(var i=0; i < tagparts.length; i++) {
    report("ADDTAG: " + tagparts[i].text + " " + tagparts[i].currentlyediting);
    var addme = tagparts[i].text;
    if(tagparts[i].currentlyediting == true) {
      addme = tag;
      addedtag = true;
    }
    append(addme);
  }
  if (!addedtag) {
    append(tag);
  }
  tagsBox.value += ' ';
  tagsBox.focus();
  lastCaretPos = getCaretPosition(tagsBox);
  if(clear) { clearsuggestions(); }
}

function clearsuggestions() {
  document.getElementById('add-form-ac-results-suggest').innerHTML = '';
  disable('tbox-all-usage') 
  disable('tbox-all-alpha') 
  disable('tbox-suggest') 
  enable('tbox-closed') 
}

function showAllUsage() {
  clearsuggestions();
  if (!usageBoxDone) {
    var list = new Array();
    for(var tag in tags) {
      list.push({ 'tag' : tag, 'uOrder' : tags[tag] });
    } 
    list.sort(usageorder);
    for(var i=0; i < list.length; i++) {
      addsuggestion('add-form-ac-results-usage', list[i].tag, false);
    }
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
    for(var tag in tags) {
      addsuggestion('add-form-ac-results-alpha', tag, false);
    }
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
  disable('tbox-all-usage') 
  disable('tbox-all-alpha') 
  disable('tbox-suggest') 
  enable('tbox-closed') 
}

function enable(id) {
  //report("enable " + id);
  var el = document.getElementById(id);
  el.style.display = '';
}

function disable(id) {
  //report("disable " + id);
  var el = document.getElementById(id);
  el.style.display = 'none';
}

function usageorder(a, b) {
  return a.uOrder - b.uOrder;
}

function analyseTagString(tagString, caretPos) {
  var tagParts = new Array();
  var all = tagString.split('');
  //report("ATS: split into: " + all.length);

  var inQuote = false;
  var inTag = false;
  var part = { text: '', currentlyediting: false };

  for (var i = 0; i < all.length; i++) {
    var c = all[i];
    //report("C: " + all[i]);
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
    else if (c == '"' || c == "'") {
      if (!inTag) {
	inTag = true;
	inQuote = true;
	continue;
      }
      else if (inQuote) {
	tagParts.push(part);
	part = { text: '', currentlyediting: false };
	inTag = inQuote = false;
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
	inTag = inQuote = false;
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
  if (part.text.length) {
    tagParts.push(part);
  }
  return tagParts;
}

function autocompletetags() {
  var tagsBox = document.getElementById('tagsbox');
  var tagstring = tagsBox.value;

  lastCaretPos = getCaretPosition(tagsBox);
  report("TS: " + tagstring + " SS: " + lastCaretPos);

  clearsuggestions();

  if (tagstring.length == 0) {
    return;
  }

  var tagparts = analyseTagString(tagstring, lastCaretPos);

  potentials = new Array();
  for(var i=0; i < tagparts.length; i++) {
    if(tagparts[i].currentlyediting != true) {continue;}
    var lctagpart = tagparts[i].text.toLowerCase();
    //report("TP: " + tagparts[i].text);

    if(lctagpart == '') { continue; }

    for (var tag in tags) {
      //report("C: " + tag);
      var lctag = tag.toLowerCase();
      if(lctag.indexOf(lctagpart) == 0) {
	//report("P: " + tag);
        //potentials.push(tag);
        potentials.push( { 'tag' : tag, 'uOrder' : tags[tag] } );
      }
    }
  }
  
  if (potentials.length)
      showSuggestByPreference();
}

function showSuggestAlpha() {

  clearsuggestions();

  for(var i=0; i< potentials.length; i++) {
    addsuggestion('add-form-ac-results-suggest', potentials[i].tag, true);
  }

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
  for(var i=0; i< potentials.length; i++) {
    addsuggestion('add-form-ac-results-suggest', alphaPotentials[i].tag, true);
  }

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
  if (input.setSelectionRange) {
    cPos = input.selectionStart;
  }
  /*
   * One IE way
   */
  else if (document.selection) {
    var range = document.selection.createRange();
    var maxMoveRight = range.move('character', 1000);
    cPos = input.value.length - maxMoveRight;
  }
  
  //report ("CPOS: " + cPos);
  return cPos;
}

function fixsize() {
  window.resizeTo(rec_popup_width(), rec_popup_height());
}

function reportReady() {
  report("ready");

  report("SCREEN HEIGHT: " + screen.height);
  report("WINDOW HEIGHT: " + getWindowHeight());
  //showDivSize(document.getElementById('add-form-ac-results'));
  //showDivSize(document.body);
}

function getWindowHeight() {
  var total = 0;

  if (document.selection) {	// IE
    for (var el = document.body; el; el = el.offsetParent) {
      total += el.offsetHeight;
    }
    //report("IEWINHEIGHT: " + total);
  }
  else {
    total = window.outerHeight;
    //report("FFWINHEIGHT: " + total);
  }
  return total;
}

function sizeCheck() {
  var windowHeight = getWindowHeight();
  var screenHeight = screen.availHeight;

  if (screenHeight > windowHeight) {
    window.resizeBy(0, ((screenHeight - windowHeight) / 2));
  }
}

function makeReportWindow() {
  if (!reportWindow || reportWindow.closed) {
    reportWindow = window.open("", "report", "height=600,width=300,resizable,scrollbars");
    setTimeout("initReportWindow()", 100);
  }
}

function initReportWindow() {
  var content = '<html><head><title>report</title></head><body><h3>Report</h3><div id="report"></div></body></html>';
  reportWindow.document.write(content);
  reportWindow.document.close();
}

function report(s) {
  if (! reportWindow)
      return;
  var r = reportWindow.document.getElementById('report');
  r.innerHTML += s + '<br/>';
}
