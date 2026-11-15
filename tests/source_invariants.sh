#!/bin/sh
# Regression checks for IOKit paths that cannot be executed on the host.
# These assert the lifecycle ordering and guard placement the audit requires.

set -u

CPP="RealtekRTL8100/RealtekRTL8100.cpp"
FAIL=0

pass() { printf 'ok - %s\n' "$1"; }
fail() { printf 'not ok - %s\n' "$1"; FAIL=1; }

extract() {
    awk -v sig="$1" 'index($0, sig) && $0 !~ /;[[:space:]]*$/ { found = 1 } found { print } found && /^}/ { exit }' "$CPP"
}

line_of() {
    printf '%s\n' "$1" | grep -n "$2" | head -n 1 | cut -d: -f1
}

# stop() must disable the interface before detaching it and before freeing DMA.
STOP=$(extract 'void RTL8100::stop(IOService *provider)')
DISABLE_LINE=$(line_of "$STOP" 'disable(netif)')
DETACH_LINE=$(line_of "$STOP" 'detachInterface(netif)')
FREE_LINE=$(line_of "$STOP" 'freeDMADescriptors()')
if [ -n "$DISABLE_LINE" ] && [ -n "$DETACH_LINE" ] && [ -n "$FREE_LINE" ] &&
   [ "$DISABLE_LINE" -lt "$DETACH_LINE" ] && [ "$DISABLE_LINE" -lt "$FREE_LINE" ]; then
    pass "stop disables before detach and DMA free"
else
    fail "stop does not disable before detach and DMA free"
fi

# setupMediumDict() must handle a failed dictionary allocation.
MEDIUM=$(extract 'bool RTL8100::setupMediumDict()')
if printf '%s\n' "$MEDIUM" | grep -q 'if (!mediumDict)' &&
   printf '%s\n' "$MEDIUM" | grep -q 'if (mediumDict)'; then
    pass "setupMediumDict guards a NULL dictionary"
else
    fail "setupMediumDict can dereference a NULL dictionary"
fi

# enable() must close the PCI device when DMA setup fails.
ENABLE=$(extract 'IOReturn RTL8100::enable(IONetworkInterface *netif)')
DMA_FAIL=$(printf '%s\n' "$ENABLE" | awk '/if \(!setupDMADescriptors\(\)\)/ { found = 1 } found { print } found && /goto done;/ { exit }')
if printf '%s\n' "$DMA_FAIL" | grep -q 'pciDevice->close(this)'; then
    pass "enable closes PCI after a DMA setup failure"
else
    fail "enable leaves PCI open after a DMA setup failure"
fi

# The watchdog must retry descriptor allocation after a failed link-down reinit.
TIMER=$(extract 'void RTL8100::timerActionRTL8100(IOTimerEventSource *timer)')
if printf '%s\n' "$TIMER" | grep -q 'setupDMADescriptors()' &&
   printf '%s\n' "$TIMER" | grep -q '!rxDescArray'; then
    pass "watchdog retries descriptor allocation"
else
    fail "watchdog never retries a failed descriptor allocation"
fi

# enableEEE is a bool, not an OSBoolean pointer.
PARAMS=$(extract 'void RTL8100::getParams()')
if printf '%s\n' "$PARAMS" | grep -q 'getValue()' &&
   ! printf '%s\n' "$PARAMS" | grep -q 'enableEEE = OSDynamicCast'; then
    pass "enableEEE reads the OSBoolean value"
else
    fail "enableEEE assigns an OSBoolean pointer to bool"
fi

# The IPv6 wrapper must pass the real mbuf length into the bounds-checked helper.
ADJUST=$(extract 'static inline UInt32 adjustIPv6Header(mbuf_t m)')
if printf '%s\n' "$ADJUST" | grep -q 'rtl8100AdjustIPv6Header(mbuf_data(m), mbuf_len(m)'; then
    pass "adjustIPv6Header passes the mbuf length"
else
    fail "adjustIPv6Header does not pass the mbuf length"
fi

# Multicast filtering must use the 64-bit helper, never a 32-bit shift.
MULTICAST=$(extract 'IOReturn RTL8100::setMulticastList(IOEthernetAddress *addrs, UInt32 count)')
if printf '%s\n' "$MULTICAST" | grep -q 'rtl8100MulticastFilter' &&
   ! printf '%s\n' "$MULTICAST" | grep -q '1 <<'; then
    pass "setMulticastList uses the 64-bit filter"
else
    fail "setMulticastList still uses a 32-bit shift"
fi

# outputStart must initialize checksum flags before asking the stack.
OUTPUT=$(extract 'IOReturn RTL8100::outputStart(IONetworkInterface *interface, IOOptionBits options )')
INIT_LINE=$(line_of "$OUTPUT" 'checksums = 0;')
REQUEST_LINE=$(line_of "$OUTPUT" 'mbuf_get_csum_requested')
if [ -n "$INIT_LINE" ] && [ -n "$REQUEST_LINE" ] && [ "$INIT_LINE" -lt "$REQUEST_LINE" ]; then
    pass "outputStart initializes checksum flags"
else
    fail "outputStart can read uninitialized checksum flags"
fi

# RxConfig base bits must survive the promiscuous and multicast writes.
PROMISC=$(extract 'IOReturn RTL8100::setPromiscuousMode(bool active)')
MULTICASTMODE=$(extract 'IOReturn RTL8100::setMulticastMode(bool active)')
if printf '%s\n' "$PROMISC" | grep -q 'rxConfigBase' &&
   printf '%s\n' "$MULTICASTMODE" | grep -q 'rxConfigBase'; then
    pass "RxConfig base is preserved by the packet filter writes"
else
    fail "RxConfig base is cleared by a packet filter write"
fi

# startRTL8100 must program the per-chip RxConfig base, not a bare DMA burst.
START=$(extract 'void RTL8100::startRTL8100(UInt16 newIntrMitigate, bool enableInterrupts)')
if printf '%s\n' "$START" | grep -q 'WriteReg32(RxConfig, rxConfigBase)'; then
    pass "startRTL8100 programs the per-chip RxConfig base"
else
    fail "startRTL8100 programs a bare RxConfig value"
fi

# rxInterrupt must drop error frames and reject lengths below the CRC size.
RX=$(extract 'UInt32 RTL8100::rxInterrupt(IONetworkInterface *interface, uint32_t maxCount, IOMbufQueue *pollQueue, void *context)')
if printf '%s\n' "$RX" | grep -q 'rtl8100RxFrameError' &&
   printf '%s\n' "$RX" | grep -q 'rtl8100RxPayloadSize'; then
    pass "rxInterrupt validates RX status and payload length"
else
    fail "rxInterrupt can deliver error frames or underflow the payload length"
fi

# No off-topic vendor message in the boot log.
if grep -q 'tonymacx86' "$CPP"; then
    fail "boot log still contains the tonymacx86 message"
else
    pass "boot log has no off-topic vendor message"
fi

# No unused interrupt threshold constant.
if grep -q 'kFastIntrTreshhold' RealtekRTL8100/RealtekRTL8100.h; then
    fail "unused kFastIntrTreshhold constant remains"
else
    pass "no unused kFastIntrTreshhold constant"
fi

# initRTL8100 must configure each chip parameter exactly once.
INIT=$(extract 'bool RTL8100::initRTL8100()')
INIT_COUNT=$(printf '%s\n' "$INIT" | grep -c 'RequireResetPhyToChgSpd = TRUE;')
if [ "$INIT_COUNT" -eq 1 ]; then
    pass "initRTL8100 configures chip parameters once"
else
    fail "initRTL8100 duplicates chip parameter setup"
fi

if [ "$FAIL" -ne 0 ]; then
    exit 1
fi

printf 'source invariants passed\n'
