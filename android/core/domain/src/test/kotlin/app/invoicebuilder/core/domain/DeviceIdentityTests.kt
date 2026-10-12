package app.invoicebuilder.core.domain

import app.invoicebuilder.core.domain.setup.DeviceIdentity
import app.invoicebuilder.core.domain.setup.DeviceMarker
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

/** `spec/setup.md` §2, ADR-0019. iOS: `DeviceIdentityTests` in `SetupRulesTests.swift`. */
class DeviceIdentityTests {
    @Test fun noRowCreatesOne() {
        assertEquals(DeviceIdentity.Action.create, DeviceIdentity.check(null, DeviceMarker.Missing))
        assertEquals(DeviceIdentity.Action.create, DeviceIdentity.check(null, DeviceMarker.Found("old"))) // reinstalled
    }

    @Test fun aMatchingMarkerKeepsTheRow() {
        assertEquals(DeviceIdentity.Action.keep, DeviceIdentity.check("d1", DeviceMarker.Found("d1")))
    }

    @Test fun aMissingOrDifferentMarkerReplacesTheId() {
        assertEquals(DeviceIdentity.Action.replace, DeviceIdentity.check("d1", DeviceMarker.Missing)) // restored onto a new phone
        assertEquals(DeviceIdentity.Action.replace, DeviceIdentity.check("d1", DeviceMarker.Found("d2"))) // another device's database
    }

    @Test fun anUnreadableMarkerNeverChangesTheId() {
        assertEquals(DeviceIdentity.Action.keep, DeviceIdentity.check("d1", DeviceMarker.Unreadable))
    }
}
