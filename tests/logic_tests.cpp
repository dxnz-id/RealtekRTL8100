#include "../RealtekRTL8100/RealtekRTL8100Logic.h"

#include <assert.h>
#include <stdio.h>
#include <string.h>

static void put_be16(unsigned char *p, unsigned int value)
{
    p[0] = (unsigned char)(value >> 8);
    p[1] = (unsigned char)value;
}

static unsigned int get_be16(const unsigned char *p)
{
    return ((unsigned int)p[0] << 8) | p[1];
}

static void test_multicast_sets_bits_above_31(void)
{
    unsigned char addr35[6] = {0x01, 0x00, 0x5e, 0x00, 0x00, 0x04};
    unsigned char addr36[6] = {0x33, 0x33, 0x00, 0x00, 0x00, 0x00};
    uint64_t filter;

    filter = rtl8100MulticastFilter(addr35, 1);
    assert(filter & ((uint64_t)1 << 35));
    assert(!(filter & ((uint64_t)1 << 3)));

    filter = rtl8100MulticastFilter(addr36, 1);
    assert(filter & ((uint64_t)1 << 36));
    assert(!(filter & ((uint64_t)1 << 4)));
}

static void test_multicast_combines_addresses(void)
{
    unsigned char addrs[2][6] = {
        {0x01, 0x00, 0x5e, 0x00, 0x00, 0x04},
        {0x33, 0x33, 0x00, 0x00, 0x00, 0x00}
    };
    uint64_t filter = rtl8100MulticastFilter(&addrs[0][0], 2);

    assert(filter & ((uint64_t)1 << 35));
    assert(filter & ((uint64_t)1 << 36));
}

static void test_multicast_empty_and_overflow(void)
{
    assert(rtl8100MulticastFilter(NULL, 0) == 0);
    assert(rtl8100MulticastFilter(NULL, RTL8100_MC_FILTER_LIMIT + 1) == ~(uint64_t)0);
}

static void test_adjust_ipv6_header_valid(void)
{
    unsigned char packet[74];
    uint32_t adjusted = 0;

    memset(packet, 0, sizeof(packet));
    put_be16(packet + 14 + 4, 32);
    put_be16(packet + 14 + 40 + 16, 0x1234);

    assert(rtl8100AdjustIPv6Header(packet, sizeof(packet), &adjusted));
    assert(adjusted == 32 + 54);
    assert(get_be16(packet + 14 + 4) == 0);
    assert(get_be16(packet + 14 + 40 + 16) == 0x1214);
}

static void test_adjust_ipv6_header_accepts_exact_minimum(void)
{
    unsigned char packet[74];

    memset(packet, 0, sizeof(packet));
    assert(rtl8100AdjustIPv6Header(packet, sizeof(packet), NULL));
}

static void test_adjust_ipv6_header_rejects_short_packet(void)
{
    unsigned char packet[74];
    uint32_t adjusted = 0xdeadbeef;

    memset(packet, 0, sizeof(packet));
    put_be16(packet + 14 + 4, 32);
    put_be16(packet + 14 + 40 + 16, 0x1234);

    assert(!rtl8100AdjustIPv6Header(packet, 54, &adjusted));
    assert(adjusted == 0xdeadbeef);
    assert(get_be16(packet + 14 + 4) == 32);
    assert(get_be16(packet + 14 + 40 + 16) == 0x1234);

    assert(!rtl8100AdjustIPv6Header(packet, 73, &adjusted));
    assert(get_be16(packet + 14 + 4) == 32);
    assert(get_be16(packet + 14 + 40 + 16) == 0x1234);
}

static void test_adjust_ipv6_header_rejects_null(void)
{
    assert(!rtl8100AdjustIPv6Header(NULL, 74, NULL));
}

int main(void)
{
    test_multicast_sets_bits_above_31();
    test_multicast_combines_addresses();
    test_multicast_empty_and_overflow();
    test_adjust_ipv6_header_valid();
    test_adjust_ipv6_header_accepts_exact_minimum();
    test_adjust_ipv6_header_rejects_short_packet();
    test_adjust_ipv6_header_rejects_null();

    printf("logic tests passed\n");
    return 0;
}
