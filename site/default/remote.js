function addTo[% codename %] (url, title) {
    if (url == undefined) url = window.location;
    var w = open('[% location %]addpopup?continue=confirm&uri='+window.encodeURIComponent(url)+(title?'&usertitle='+window.encodeURIComponent(title):''),'add','width=720,height=755,scrollbars,resizable');
    void(window.setTimeout('w.focus()',200));
}
