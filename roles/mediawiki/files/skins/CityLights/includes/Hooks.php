<?php
/**
 * City Lights skin — hook handlers.
 *
 * @file
 */

namespace MediaWiki\Skins\CityLights;

use MediaWiki\Hook\BeforePageDisplayHook;

/**
 * Hook handlers for the City Lights skin.
 */
class Hooks implements BeforePageDisplayHook {

	/**
	 * Load the City Lights theme stylesheet as a raw <link>, scoped to the
	 * City Lights skin.
	 *
	 * The theme is loaded here rather than as a ResourceLoader style module
	 * on purpose. ResourceLoader concatenates a style bundle in module-name
	 * order, which places skins.citylights.* before skins.vector.styles —
	 * so Vector's rules, declared last, would win the cascade. A raw
	 * stylesheet added via OutputPage::addStyle() is emitted after the whole
	 * ResourceLoader bundle, so the City Lights theme reliably overrides
	 * Vector's defaults.
	 *
	 * The skin-name guard keeps the stylesheet off Vector 2022 and Vector
	 * Legacy: the hook fires for every skin, but only City Lights reports
	 * the 'citylights' skin name.
	 *
	 * @param \OutputPage $out
	 * @param \Skin $skin
	 * @return void
	 */
	public function onBeforePageDisplay( $out, $skin ): void {
		if ( $skin->getSkinName() !== 'citylights' ) {
			return;
		}
		$out->addStyle(
			$out->getConfig()->get( 'ScriptPath' )
				. '/skins/CityLights/resources/citylights-wiki.css'
		);
	}
}
