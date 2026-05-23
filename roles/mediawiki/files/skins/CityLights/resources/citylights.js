/* City Lights skin — runtime behaviours
 *
 * Loaded as the skins.citylights.scripts ResourceLoader module, listed in
 * the skin's `scripts` so it runs only for the City Lights skin — never
 * for Vector 2022 or Vector Legacy. Two pieces: collapse the empty
 * #siteNotice wrapper, and relocate the page-title header into the
 * content panel.
 */

/* Sitenotice — the .vector-sitenotice-container wrapper is emitted on
   every page and given a 2rem min-height by citylights-wiki.css. When
   there is nothing to show (blank MediaWiki:Sitenotice, or the campus
   notice was dismissed) collapse the whole container so the reserved
   strip disappears with it — display:none beats the min-height. */
(function () {
	var k = 'cttb-notice-dismissed-4';
	var box = document.querySelector('.vector-sitenotice-container #siteNotice');
	var sn = document.getElementById('siteNotice');
	var notice = document.getElementById('cttb-notice');
	var btn = document.getElementById('cttb-notice-dismiss');

	if (box == undefined) {
		box = document.querySelector('.vector-sitenotice-container');
	}

	function hideBox() { var t = box || sn; if (t) t.style.display = 'none'; }

	/* Blank Sitenotice page — wrapper present but no real text. */
	if (sn && !sn.textContent.trim()) hideBox();

	/* Campus notice dismissed on an earlier visit. */
	if (notice && localStorage.getItem(k)) {
		notice.style.display = 'none';
		hideBox();
	}

	/* Dismiss button — hide the notice and collapse the container. */
	if (btn) btn.addEventListener('click', function () {
		notice.style.display = 'none';
		localStorage.setItem(k, '1');
		hideBox();
	});
})();

/* Relocate the whole page-title header into the content panel — it
   otherwise floats above the toolbar card. Idempotent: the parentNode
   guard makes re-fires of wikipage.content a no-op. */
mw.hook('wikipage.content').add(function () {
	var h = document.querySelector('.mw-body-header');
	var b = document.getElementById('bodyContent');
	if (h && b && h.parentNode !== b) b.prepend(h);
});
