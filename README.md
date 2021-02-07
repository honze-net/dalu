# Deploy Arch Linux Unattended

This is a working example for an unattended deployment script for Arch Linux.
It tries to stay parallel to the official Arch Linux installation guide.
A fairly linear structure reduces the complexity for human readers.
The arch-chroot part is wrapped into a bash function, that gets exported to the arch-chroot environment.
(So no arbitrary copying of setup scripts into the arch-chroot.)
For debugging purposes it writes extensive logs.

This example should serve as a pattern for scripting an Arch Linux deployment.

## Usage
It is highly recommended to test this in a virtual environment first.
1. Change the example script to fit your needs.
2. Copy it to an Arch ISO live environment.
3. Execute the script.
4. Wait for completion.
5. Reboot into your new Arch system.
