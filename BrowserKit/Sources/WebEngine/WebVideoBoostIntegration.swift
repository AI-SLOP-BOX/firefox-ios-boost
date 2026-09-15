// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import WebVideoBoost

/// Entry point for Client-side WebVideoBoost hooks, so Client targets
/// don't need a direct dependency on the WebVideoBoost package.
public enum WebVideoBoostIntegration {
    public static func handleAppDidEnterBackground() {
        WebVideoBoost.didEnterBackgroundAll()
    }
}
