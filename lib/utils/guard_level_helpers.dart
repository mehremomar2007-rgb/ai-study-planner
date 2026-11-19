import 'package:flutter/material.dart';

import 'package:ai_study_planner/localization/app_localization.dart';
import 'package:ai_study_planner/models/models.dart';
import 'package:ai_study_planner/theme/app_colors.dart';

Color levelColor(GuardLevel l) => switch (l) {
      GuardLevel.safe => kGreen,
      GuardLevel.warning => kOrange,
      GuardLevel.over => kRed,
    };

String levelMessage(GuardLevel l) => switch (l) {
      GuardLevel.safe => tr('ماشي تمام، كمّل بنفس الإيقاع.'),
      GuardLevel.warning => tr('قربت من الحد الآمن، خد استراحة قريب.'),
      GuardLevel.over => tr('عديت الحد الآمن النهاردة. وقّف وارتاح.'),
    };
