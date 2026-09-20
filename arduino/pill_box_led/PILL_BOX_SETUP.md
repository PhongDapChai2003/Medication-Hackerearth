# Smart pill box setup: 10 compartments

This version uses 10 ordinary two-leg LEDs and 10 normally-open lid switches in a 2 x 5 arrangement. D11 is not used.

## Pin map

### LEDs

- LED row 1: D2 through a 470 ohm resistor
- LED row 2: D3 through a 470 ohm resistor
- LED columns 1-5: A0, A1, A2, A3, A4

Connect each LED long leg (anode) to its column. Connect its short or flat-side leg (cathode) to its row. The program lights only one compartment at a time.

### Lid switches

- Switch rows: D4 and D5
- Switch columns: D6, D7, D8, D9, D10
- Use the COM and normally-open terminals so the switch reads LOW when the lid is opened.
- D11 is unused.

If several lids may be open together, add one isolation diode to each switch to prevent false matrix readings.

### Buzzer

- Buzzer signal: A5
- Buzzer ground: GND

Use a suitable transistor driver if the buzzer requires more current than an Arduino pin can safely supply.

## Compartment order

Top row: 1, 2, 3, 4, 5

Bottom row: 6, 7, 8, 9, 10

## Behavior

1. At medication time, the phone sends the assigned compartment number.
2. The correct compartment LED blinks.
3. Opening the correct lid changes the LED to a steady light.
4. Closing the correct lid turns the LED off.
5. Opening a wrong lid makes the buzzer beep three times.

## Upload and test

1. Disconnect USB power before changing any wiring.
2. Connect only one LED, one switch, and the buzzer for the first test.
3. Reconnect the UNO R4 WiFi by USB.
4. Open pill_box_led.ino in Arduino IDE.
5. Select Arduino UNO R4 WiFi and its USB port.
6. Select Verify, then Upload.
7. Open Serial Monitor at 115200 baud.

## Connect the phone app

1. Connect the phone to Medication-Pill-Box.
2. Use password pillbox21.
3. Open Settings -> Smart Pill Box.
4. Keep the Arduino address as 192.168.4.1.
5. Select Test connection.
6. Add or edit a medication and assign it to compartment 1-10.

The assigned light can start automatically at its reminder minute while the app is running and the phone is connected to the pill-box Wi-Fi. Tapping a medication notification also attempts to send the command. A notification appearing while the app is completely closed cannot reliably run this local network request on every phone.
