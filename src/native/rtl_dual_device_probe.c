/*
 * rtl_dual_device_probe.c
 *
 * Application-owned RTL-SDR role discovery baseline for RTL-Windows-ADS-B-Tracker.
 *
 * Device identity is based on EEPROM serial numbers:
 *   00001090 = ADS-B receiver
 *   00000162 = NOAA / Airband audio receiver
 *
 * Important Windows behavior observed during initial validation:
 * Do not launch separate workers that concurrently enumerate devices by serial.
 * This program enumerates sequentially, resolves indexes, and then opens the
 * devices by their resolved indexes.
 */

#include <rtl-sdr.h>

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define DEFAULT_ADSB_SERIAL  "00001090"
#define DEFAULT_AUDIO_SERIAL "00000162"

#define ADSB_FREQ_HZ  1090000000U
#define ADSB_RATE_HZ  2400000U
#define AUDIO_FREQ_HZ 162500000U
#define AUDIO_RATE_HZ 1008000U

#define USB_STRING_CAPACITY 256
#define READ_BUFFER_BYTES   65536

typedef struct device_role {
    const char *label;
    const char *serial;
    uint32_t index;
    int found;
} device_role_t;

static void print_usage(const char *program)
{
    fprintf(stderr,
            "Usage: %s [--open-test] [--json] "
            "[--adsb-serial SERIAL] [--audio-serial SERIAL]\n",
            program);
}

static const char *tuner_name(enum rtlsdr_tuner tuner)
{
    switch (tuner) {
    case RTLSDR_TUNER_E4000:  return "E4000";
    case RTLSDR_TUNER_FC0012: return "FC0012";
    case RTLSDR_TUNER_FC0013: return "FC0013";
    case RTLSDR_TUNER_FC2580: return "FC2580";
    case RTLSDR_TUNER_R820T:  return "R820T";
    case RTLSDR_TUNER_R828D:  return "R828D";
    default:                   return "UNKNOWN";
    }
}

static int resolve_roles(device_role_t *adsb, device_role_t *audio, int json)
{
    uint32_t count = rtlsdr_get_device_count();
    uint32_t index;

    if (!json) {
        printf("Detected RTL-SDR devices: %u\n", count);
    }

    for (index = 0; index < count; ++index) {
        char manufacturer[USB_STRING_CAPACITY] = {0};
        char product[USB_STRING_CAPACITY] = {0};
        char serial[USB_STRING_CAPACITY] = {0};
        int result = rtlsdr_get_device_usb_strings(index, manufacturer, product, serial);

        if (result != 0) {
            fprintf(stderr, "Unable to read USB identity for RTL index %u (error %d).\n",
                    index, result);
            continue;
        }

        if (!json) {
            printf("  index %u: manufacturer=\"%s\" product=\"%s\" serial=\"%s\"\n",
                   index, manufacturer, product, serial);
        }

        if (strcmp(serial, adsb->serial) == 0) {
            adsb->index = index;
            adsb->found = 1;
        }
        if (strcmp(serial, audio->serial) == 0) {
            audio->index = index;
            audio->found = 1;
        }
    }

    if (!adsb->found || !audio->found || adsb->index == audio->index) {
        if (json) {
            printf("{\"ok\":false,\"device_count\":%u,"
                   "\"error\":\"required receiver serial mapping not found\"}\n",
                   count);
        } else {
            fprintf(stderr,
                    "Required roles were not resolved: ADS-B %s=%s, Audio %s=%s.\n",
                    adsb->serial, adsb->found ? "found" : "missing",
                    audio->serial, audio->found ? "found" : "missing");
        }
        return -1;
    }

    if (json) {
        printf("{\"ok\":true,\"device_count\":%u,"
               "\"adsb\":{\"serial\":\"%s\",\"index\":%u},"
               "\"audio\":{\"serial\":\"%s\",\"index\":%u}}\n",
               count, adsb->serial, adsb->index, audio->serial, audio->index);
    } else {
        printf("\nResolved fixed receiver roles:\n");
        printf("  ADS-B        serial %s -> index %u\n", adsb->serial, adsb->index);
        printf("  NOAA/Airband serial %s -> index %u\n", audio->serial, audio->index);
    }

    return 0;
}

static int open_and_configure(rtlsdr_dev_t **device,
                              const device_role_t *role,
                              uint32_t frequency_hz,
                              uint32_t sample_rate_hz)
{
    int result;

    result = rtlsdr_open(device, role->index);
    if (result != 0) {
        fprintf(stderr, "Unable to open %s receiver at index %u (error %d).\n",
                role->label, role->index, result);
        return -1;
    }

    result = rtlsdr_set_tuner_gain_mode(*device, 0);
    if (result != 0) {
        fprintf(stderr, "Unable to set automatic gain for %s receiver (error %d).\n",
                role->label, result);
        return -1;
    }

    result = rtlsdr_set_sample_rate(*device, sample_rate_hz);
    if (result != 0) {
        fprintf(stderr, "Unable to set sample rate for %s receiver (error %d).\n",
                role->label, result);
        return -1;
    }

    result = rtlsdr_set_center_freq(*device, frequency_hz);
    if (result != 0) {
        fprintf(stderr, "Unable to tune %s receiver to %u Hz (error %d).\n",
                role->label, frequency_hz, result);
        return -1;
    }

    result = rtlsdr_reset_buffer(*device);
    if (result != 0) {
        fprintf(stderr, "Unable to reset %s receiver buffer (error %d).\n",
                role->label, result);
        return -1;
    }

    printf("Opened %s: index=%u serial=%s tuner=%s frequency=%u Hz sample_rate=%u S/s\n",
           role->label, role->index, role->serial, tuner_name(rtlsdr_get_tuner_type(*device)),
           frequency_hz, rtlsdr_get_sample_rate(*device));
    return 0;
}

static int run_dual_open_test(const device_role_t *adsb, const device_role_t *audio)
{
    rtlsdr_dev_t *adsb_device = NULL;
    rtlsdr_dev_t *audio_device = NULL;
    unsigned char *buffer = NULL;
    int read_bytes = 0;
    int status = -1;

    buffer = (unsigned char *)malloc(READ_BUFFER_BYTES);
    if (buffer == NULL) {
        fprintf(stderr, "Unable to allocate read buffer.\n");
        return -1;
    }

    printf("\nOpening and configuring ADS-B receiver first...\n");
    if (open_and_configure(&adsb_device, adsb, ADSB_FREQ_HZ, ADSB_RATE_HZ) != 0) {
        goto cleanup;
    }

    printf("Opening and configuring NOAA/Airband receiver second...\n");
    if (open_and_configure(&audio_device, audio, AUDIO_FREQ_HZ, AUDIO_RATE_HZ) != 0) {
        goto cleanup;
    }

    if (rtlsdr_read_sync(adsb_device, buffer, READ_BUFFER_BYTES, &read_bytes) != 0 ||
        read_bytes != READ_BUFFER_BYTES) {
        fprintf(stderr, "ADS-B synchronous read failed or was short: %d bytes.\n", read_bytes);
        goto cleanup;
    }
    printf("Read %d bytes from ADS-B receiver while both handles are open.\n", read_bytes);

    read_bytes = 0;
    if (rtlsdr_read_sync(audio_device, buffer, READ_BUFFER_BYTES, &read_bytes) != 0 ||
        read_bytes != READ_BUFFER_BYTES) {
        fprintf(stderr, "NOAA/Airband synchronous read failed or was short: %d bytes.\n",
                read_bytes);
        goto cleanup;
    }
    printf("Read %d bytes from NOAA/Airband receiver while both handles are open.\n",
           read_bytes);

    printf("\nPASS: Application-owned sequential role discovery and dual-handle open/read test completed.\n");
    status = 0;

cleanup:
    if (audio_device != NULL) {
        rtlsdr_close(audio_device);
    }
    if (adsb_device != NULL) {
        rtlsdr_close(adsb_device);
    }
    free(buffer);
    return status;
}

int main(int argc, char **argv)
{
    const char *adsb_serial = DEFAULT_ADSB_SERIAL;
    const char *audio_serial = DEFAULT_AUDIO_SERIAL;
    int open_test = 0;
    int json = 0;
    int i;

    device_role_t adsb = {"ADS-B", NULL, 0U, 0};
    device_role_t audio = {"NOAA/Airband", NULL, 0U, 0};

    for (i = 1; i < argc; ++i) {
        if (strcmp(argv[i], "--open-test") == 0) {
            open_test = 1;
        } else if (strcmp(argv[i], "--json") == 0) {
            json = 1;
        } else if (strcmp(argv[i], "--adsb-serial") == 0 && i + 1 < argc) {
            adsb_serial = argv[++i];
        } else if (strcmp(argv[i], "--audio-serial") == 0 && i + 1 < argc) {
            audio_serial = argv[++i];
        } else {
            print_usage(argv[0]);
            return EXIT_FAILURE;
        }
    }

    if (json && open_test) {
        fprintf(stderr, "--json and --open-test are separate operating modes.\n");
        return EXIT_FAILURE;
    }

    adsb.serial = adsb_serial;
    audio.serial = audio_serial;

    if (resolve_roles(&adsb, &audio, json) != 0) {
        return EXIT_FAILURE;
    }

    if (open_test && run_dual_open_test(&adsb, &audio) != 0) {
        return EXIT_FAILURE;
    }

    return EXIT_SUCCESS;
}
