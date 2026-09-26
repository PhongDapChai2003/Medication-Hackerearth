# Smart pill box setup: 7-compartment Bluetooth red/green matrix

This version follows the 3 x 7 matrix drawing. Each compartment has one
three-leg common-anode red/green LED and one normally-open magnetic reed
switch. The LED and sensor share the compartment column. Each reed branch
requires a 1N4148 isolation diode so closed lids cannot connect LED columns
together and create ghost lights.

## Pin map

- D2: all red LED cathodes
- D3: all green LED cathodes
- D4: common reed-switch row
- D5: compartment 1 column
- D6: compartment 2 column
- D7: compartment 3 column
- D8: compartment 4 column
- D9: compartment 5 column
- D10: compartment 6 column
- D11: compartment 7 column
- D12: active-buzzer signal

## LED wiring

For every compartment:

1. Connect its LED common-anode leg to its D5-D11 column through one 330-ohm,
   1/4-watt resistor.
2. Connect its red cathode to D2.
3. Connect its green cathode to D3.

The firmware lights only one color and one compartment at a time, so the red
and green dies can share the column resistor. If both colors must ever be lit
together, redesign the current limiting so each color has its own resistor.

## Magnetic reed-switch wiring

For every compartment:

1. Connect D4 to the non-striped end (anode) of a 1N4148 diode.
2. Connect the striped end (cathode) of the diode to one reed-switch lead.
3. Connect the other reed-switch lead to that compartment's D5-D11 column,
   after the column resistor.
4. Put the magnet on the moving lid and the reed switch on the fixed box.

Use seven 1N4148 diodes total, one for each reed switch. The stripe must face
the compartment column. Without these diodes, several closed lids can connect
the columns together and illuminate the wrong LEDs.

The specified reed switch is normally open. With the magnet near the switch,
the closed lid closes the electrical contact. Opening the lid moves the magnet
away and opens the contact. The firmware handles this inverted lid logic.

## Active buzzer wiring

- VCC: Arduino 5V
- GND: Arduino GND
- I/O or SIG: D12

The selected module is treated as low-level triggered: D12 LOW sounds it and
D12 HIGH turns it off. If the physical module behaves in reverse, swap the two
levels in `wrongLidAlarm()` and `configureHardware()`.

## Behavior

1. At a saved medication time, the assigned compartment turns solid green.
2. Opening the correct lid turns the green light off and completes the reminder.
3. Opening a wrong lid makes that wrong compartment blink red and repeats a
   quieter original two-chirp alert. The correct compartment remains visibly
   green while the wrong red light blinks.
4. Closing the wrong lid stops the buzzer and restores the correct green light.
5. The Arduino scans LEDs and reed switches at different times so their shared
   matrix connections do not fight each other.

## Upload and test

1. Disconnect USB power before changing wiring.
2. First connect only compartment 1: its LED, 330-ohm resistor, 1N4148 diode,
   and reed switch.
3. Check for accidental 5V-to-GND shorts with a multimeter.
4. Reconnect the UNO R4 WiFi by USB.
5. Open `pill_box_led.ino` in Arduino IDE.
6. Select **Arduino UNO R4 WiFi** and the detected USB port.
7. Select Verify, then Upload.
8. Open Serial Monitor at 115200 baud.
9. Confirm startup shows red then green for each connected compartment.
10. In the app, connect by Bluetooth and test compartment 1 before connecting
    the remaining six.

For an incremental breadboard test, disconnected reed inputs are ignored. A
connected lid becomes active after the firmware detects it closed once. Keep
the magnet next to the reed switch before starting the reminder, then move the
magnet away to test an opening.

## Connect the phone app by Bluetooth

1. Keep the UNO R4 WiFi powered and near the phone.
2. Keep the phone on its normal Wi-Fi or mobile data; do not change networks.
3. Turn on Bluetooth on the phone.
4. Open Settings -> Smart Pill Box.
5. Select **Connect pill box** and allow Bluetooth access when asked.
6. Assign each medication to compartment 1-7.

The app uploads the saved medication schedule and clock after Bluetooth
connects. The Arduino can then turn the assigned compartment green at the saved
minute without the app staying connected, provided the board remains powered.
Opening the correct lid turns the green light off. Opening a wrong lid keeps the
correct green guide lit, blinks that wrong compartment red, and plays the alert
rhythm until the wrong lid closes.
