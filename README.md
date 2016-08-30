# StructureScannerSwift
Swift port of Structure Scanner sample app

Ported the sample to Swift and converted to using Storyboards. Added a long press to toggle between showing the tracker view since it mostly is not used an covers a bit of the screen.

I have tested this only on iPhone as I don't have an iPad. If there is a problem, it is most likely with connecting the iPad_main.storyboard.

Everything is working excpet there is a problem when running STColorizer with the option STColorizerType.TextureMapForObject. Look at ViewController.swift line 936 - 945 for details