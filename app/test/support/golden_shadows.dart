// Golden fidelity: `flutter test` shadow ko **solid silhouette** ki tarah paint
// karta hai (`debugDisableShadows = true` default hai). Isliye har golden me
// card/pill ke neeche ek dumdum kaali, hard-edge "echo" band dikhta tha jo
// asli device par kabhi nahi hota — audit me wahi band "grey ledge"/"black
// ring" jaisa bug lag raha tha.
//
// Golden ka kaam layout aur colour lock karna hai, *fake* shadow nahi. Isliye
// har golden test apne `setUpAll` me ye call karta hai.
import 'package:flutter/rendering.dart';

void useRealShadows() => debugDisableShadows = false;
