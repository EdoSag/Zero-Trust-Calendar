import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_l10n_en.dart';
import 'app_l10n_he.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppL10n
/// returned by `AppL10n.of(context)`.
///
/// Applications need to include `AppL10n.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_l10n.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppL10n.localizationsDelegates,
///   supportedLocales: AppL10n.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppL10n.supportedLocales
/// property.
abstract class AppL10n {
  AppL10n(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppL10n of(BuildContext context) {
    return Localizations.of<AppL10n>(context, AppL10n)!;
  }

  static const LocalizationsDelegate<AppL10n> delegate = _AppL10nDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('he'),
  ];

  /// No description provided for @noTitle.
  ///
  /// In en, this message translates to:
  /// **'(No title)'**
  String get noTitle;

  /// No description provided for @snooze10Min.
  ///
  /// In en, this message translates to:
  /// **'Snooze 10 min'**
  String get snooze10Min;

  /// No description provided for @map.
  ///
  /// In en, this message translates to:
  /// **'Map'**
  String get map;

  /// No description provided for @note.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get note;

  /// No description provided for @runningLate.
  ///
  /// In en, this message translates to:
  /// **'Running late'**
  String get runningLate;

  /// No description provided for @event.
  ///
  /// In en, this message translates to:
  /// **'Event'**
  String get event;

  /// No description provided for @eventReminders.
  ///
  /// In en, this message translates to:
  /// **'Event reminders'**
  String get eventReminders;

  /// No description provided for @remindersBeforeYourEvents.
  ///
  /// In en, this message translates to:
  /// **'Reminders before your events'**
  String get remindersBeforeYourEvents;

  /// No description provided for @attachment.
  ///
  /// In en, this message translates to:
  /// **'Attachment'**
  String get attachment;

  /// No description provided for @removeAttachment.
  ///
  /// In en, this message translates to:
  /// **'Remove attachment'**
  String get removeAttachment;

  /// No description provided for @image.
  ///
  /// In en, this message translates to:
  /// **'Image'**
  String get image;

  /// No description provided for @thisFileHasntFinishedUploading.
  ///
  /// In en, this message translates to:
  /// **'This file hasn\'t finished uploading from the phone that added it.'**
  String get thisFileHasntFinishedUploading;

  /// No description provided for @calendars.
  ///
  /// In en, this message translates to:
  /// **'Calendars'**
  String get calendars;

  /// No description provided for @newCalendar.
  ///
  /// In en, this message translates to:
  /// **'New calendar'**
  String get newCalendar;

  /// No description provided for @calendarsLikeEventsAreEnd.
  ///
  /// In en, this message translates to:
  /// **'Calendars, like events, are end-to-end encrypted and sync to your other devices.'**
  String get calendarsLikeEventsAreEnd;

  /// No description provided for @editCalendar.
  ///
  /// In en, this message translates to:
  /// **'Edit calendar'**
  String get editCalendar;

  /// No description provided for @name.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get name;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @itsEventsDisappearFromAll.
  ///
  /// In en, this message translates to:
  /// **'Its events disappear from all your devices. You can subscribe again any time.'**
  String get itsEventsDisappearFromAll;

  /// No description provided for @itsEventsAreDeletedToo.
  ///
  /// In en, this message translates to:
  /// **'Its events are deleted too, on all your devices. This can\'t be undone.'**
  String get itsEventsAreDeletedToo;

  /// No description provided for @allDay.
  ///
  /// In en, this message translates to:
  /// **'All day'**
  String get allDay;

  /// No description provided for @thisEventWasDeleted.
  ///
  /// In en, this message translates to:
  /// **'This event was deleted.'**
  String get thisEventWasDeleted;

  /// No description provided for @noReplyYet.
  ///
  /// In en, this message translates to:
  /// **'No reply yet'**
  String get noReplyYet;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @copyToMyCalendar.
  ///
  /// In en, this message translates to:
  /// **'Copy to my calendar'**
  String get copyToMyCalendar;

  /// No description provided for @duplicate.
  ///
  /// In en, this message translates to:
  /// **'Duplicate'**
  String get duplicate;

  /// No description provided for @shareAsIcsFile.
  ///
  /// In en, this message translates to:
  /// **'Share as .ics file'**
  String get shareAsIcsFile;

  /// No description provided for @joinVideoCall.
  ///
  /// In en, this message translates to:
  /// **'Join video call'**
  String get joinVideoCall;

  /// No description provided for @openInMaps.
  ///
  /// In en, this message translates to:
  /// **'Open in maps'**
  String get openInMaps;

  /// No description provided for @subscribedCalendarReadOnly.
  ///
  /// In en, this message translates to:
  /// **'Subscribed calendar, read-only'**
  String get subscribedCalendarReadOnly;

  /// No description provided for @emailGuests.
  ///
  /// In en, this message translates to:
  /// **'Email guests'**
  String get emailGuests;

  /// No description provided for @emailInvitation.
  ///
  /// In en, this message translates to:
  /// **'Email invitation'**
  String get emailInvitation;

  /// No description provided for @emailUpdate.
  ///
  /// In en, this message translates to:
  /// **'Email update'**
  String get emailUpdate;

  /// No description provided for @someGuestsAreNoLonger.
  ///
  /// In en, this message translates to:
  /// **'Some guests are no longer in ZT Contacts'**
  String get someGuestsAreNoLonger;

  /// No description provided for @notes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get notes;

  /// No description provided for @link.
  ///
  /// In en, this message translates to:
  /// **'Link'**
  String get link;

  /// No description provided for @noteNotAvailableYet.
  ///
  /// In en, this message translates to:
  /// **'Note not available yet'**
  String get noteNotAvailableYet;

  /// No description provided for @stillSyncingOrDeletedIn.
  ///
  /// In en, this message translates to:
  /// **'Still syncing, or deleted in ZT Notes'**
  String get stillSyncingOrDeletedIn;

  /// No description provided for @unlinkNote.
  ///
  /// In en, this message translates to:
  /// **'Unlink note'**
  String get unlinkNote;

  /// No description provided for @linkMeetingNotesAnAgenda.
  ///
  /// In en, this message translates to:
  /// **'Link meeting notes, an agenda or a packing list from ZT Notes.'**
  String get linkMeetingNotesAnAgenda;

  /// No description provided for @deleteThisEvent.
  ///
  /// In en, this message translates to:
  /// **'Delete this event?'**
  String get deleteThisEvent;

  /// No description provided for @itIsDeletedOnAll.
  ///
  /// In en, this message translates to:
  /// **'It is deleted on all your devices.'**
  String get itIsDeletedOnAll;

  /// No description provided for @thisEvent.
  ///
  /// In en, this message translates to:
  /// **'This event'**
  String get thisEvent;

  /// No description provided for @thisAndFollowingEvents.
  ///
  /// In en, this message translates to:
  /// **'This and following events'**
  String get thisAndFollowingEvents;

  /// No description provided for @allEvents.
  ///
  /// In en, this message translates to:
  /// **'All events'**
  String get allEvents;

  /// No description provided for @thisEventWasChangedBy.
  ///
  /// In en, this message translates to:
  /// **'This event was changed by a newer ZT Calendar. Update the app to edit it.'**
  String get thisEventWasChangedBy;

  /// No description provided for @discardChanges.
  ///
  /// In en, this message translates to:
  /// **'Discard changes?'**
  String get discardChanges;

  /// No description provided for @keepEditing.
  ///
  /// In en, this message translates to:
  /// **'Keep editing'**
  String get keepEditing;

  /// No description provided for @discard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get discard;

  /// No description provided for @attachAFile.
  ///
  /// In en, this message translates to:
  /// **'Attach a file'**
  String get attachAFile;

  /// No description provided for @filesCanBeUpTo.
  ///
  /// In en, this message translates to:
  /// **'Files can be up to 20 MB.'**
  String get filesCanBeUpTo;

  /// No description provided for @addGuestByEmail.
  ///
  /// In en, this message translates to:
  /// **'Add guest by email'**
  String get addGuestByEmail;

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @thatDoesntLookLikeAn.
  ///
  /// In en, this message translates to:
  /// **'That doesn\'t look like an email address.'**
  String get thatDoesntLookLikeAn;

  /// No description provided for @addReminder.
  ///
  /// In en, this message translates to:
  /// **'Add reminder'**
  String get addReminder;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @addTitle.
  ///
  /// In en, this message translates to:
  /// **'Add title'**
  String get addTitle;

  /// No description provided for @eventColour.
  ///
  /// In en, this message translates to:
  /// **'Event colour'**
  String get eventColour;

  /// No description provided for @removeReminder.
  ///
  /// In en, this message translates to:
  /// **'Remove reminder'**
  String get removeReminder;

  /// No description provided for @addLocation.
  ///
  /// In en, this message translates to:
  /// **'Add location'**
  String get addLocation;

  /// No description provided for @addVideoCallLink.
  ///
  /// In en, this message translates to:
  /// **'Add video call link'**
  String get addVideoCallLink;

  /// No description provided for @addGuestsFromZtContacts.
  ///
  /// In en, this message translates to:
  /// **'Add guests from ZT Contacts'**
  String get addGuestsFromZtContacts;

  /// No description provided for @guests.
  ///
  /// In en, this message translates to:
  /// **'Guests'**
  String get guests;

  /// No description provided for @removeGuest.
  ///
  /// In en, this message translates to:
  /// **'Remove guest'**
  String get removeGuest;

  /// No description provided for @contact.
  ///
  /// In en, this message translates to:
  /// **'Contact'**
  String get contact;

  /// No description provided for @linkANoteFromZt.
  ///
  /// In en, this message translates to:
  /// **'Link a note from ZT Notes'**
  String get linkANoteFromZt;

  /// No description provided for @addAttachment.
  ///
  /// In en, this message translates to:
  /// **'Add attachment'**
  String get addAttachment;

  /// No description provided for @encryptedOnThisPhoneBefore.
  ///
  /// In en, this message translates to:
  /// **'Encrypted on this phone before upload'**
  String get encryptedOnThisPhoneBefore;

  /// No description provided for @addDescription.
  ///
  /// In en, this message translates to:
  /// **'Add description'**
  String get addDescription;

  /// No description provided for @guest.
  ///
  /// In en, this message translates to:
  /// **'Guest'**
  String get guest;

  /// No description provided for @going.
  ///
  /// In en, this message translates to:
  /// **'Going'**
  String get going;

  /// No description provided for @maybe.
  ///
  /// In en, this message translates to:
  /// **'Maybe'**
  String get maybe;

  /// No description provided for @notGoing.
  ///
  /// In en, this message translates to:
  /// **'Not going'**
  String get notGoing;

  /// No description provided for @noPhoneNumbersOrEmail.
  ///
  /// In en, this message translates to:
  /// **'No phone numbers or email addresses for the guests.'**
  String get noPhoneNumbersOrEmail;

  /// No description provided for @ourMeeting.
  ///
  /// In en, this message translates to:
  /// **'our meeting'**
  String get ourMeeting;

  /// No description provided for @sendBy.
  ///
  /// In en, this message translates to:
  /// **'Send by'**
  String get sendBy;

  /// No description provided for @textMessage.
  ///
  /// In en, this message translates to:
  /// **'Text message'**
  String get textMessage;

  /// No description provided for @email.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get email;

  /// No description provided for @noAppToSendIt.
  ///
  /// In en, this message translates to:
  /// **'No app to send it with.'**
  String get noAppToSendIt;

  /// No description provided for @addAGuestWithAn.
  ///
  /// In en, this message translates to:
  /// **'Add a guest with an email address first.'**
  String get addAGuestWithAn;

  /// No description provided for @emailInvitationX.
  ///
  /// In en, this message translates to:
  /// **'Email invitation?'**
  String get emailInvitationX;

  /// No description provided for @emailUpdatedInvitation.
  ///
  /// In en, this message translates to:
  /// **'Email updated invitation?'**
  String get emailUpdatedInvitation;

  /// No description provided for @continueLabel.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueLabel;

  /// No description provided for @openTheAttachedInviteIcs.
  ///
  /// In en, this message translates to:
  /// **'Open the attached invite.ics to add it to your calendar.'**
  String get openTheAttachedInviteIcs;

  /// No description provided for @notSupportedOnThisDevice.
  ///
  /// In en, this message translates to:
  /// **'Not supported on this device.'**
  String get notSupportedOnThisDevice;

  /// No description provided for @schedule.
  ///
  /// In en, this message translates to:
  /// **'Schedule'**
  String get schedule;

  /// No description provided for @day.
  ///
  /// In en, this message translates to:
  /// **'Day'**
  String get day;

  /// No description provided for @s3Days.
  ///
  /// In en, this message translates to:
  /// **'3 days'**
  String get s3Days;

  /// No description provided for @week.
  ///
  /// In en, this message translates to:
  /// **'Week'**
  String get week;

  /// No description provided for @month.
  ///
  /// In en, this message translates to:
  /// **'Month'**
  String get month;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @today.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get today;

  /// No description provided for @changeView.
  ///
  /// In en, this message translates to:
  /// **'Change view'**
  String get changeView;

  /// No description provided for @quickAddEventOrTask.
  ///
  /// In en, this message translates to:
  /// **'Quick add event or task'**
  String get quickAddEventOrTask;

  /// No description provided for @newEvent.
  ///
  /// In en, this message translates to:
  /// **'New event'**
  String get newEvent;

  /// No description provided for @tasksFromZtTasks.
  ///
  /// In en, this message translates to:
  /// **'Tasks from ZT Tasks'**
  String get tasksFromZtTasks;

  /// No description provided for @birthdaysFromZtContacts.
  ///
  /// In en, this message translates to:
  /// **'Birthdays from ZT Contacts'**
  String get birthdaysFromZtContacts;

  /// No description provided for @manageCalendars.
  ///
  /// In en, this message translates to:
  /// **'Manage calendars'**
  String get manageCalendars;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @noEventsInThatFile.
  ///
  /// In en, this message translates to:
  /// **'No events in that file.'**
  String get noEventsInThatFile;

  /// No description provided for @eventUpdated.
  ///
  /// In en, this message translates to:
  /// **'Event updated'**
  String get eventUpdated;

  /// No description provided for @alreadyInYourCalendar.
  ///
  /// In en, this message translates to:
  /// **'Already in your calendar'**
  String get alreadyInYourCalendar;

  /// No description provided for @cancelledEvent.
  ///
  /// In en, this message translates to:
  /// **'Cancelled event'**
  String get cancelledEvent;

  /// No description provided for @invitation.
  ///
  /// In en, this message translates to:
  /// **'Invitation'**
  String get invitation;

  /// No description provided for @updatedInvitation.
  ///
  /// In en, this message translates to:
  /// **'Updated invitation'**
  String get updatedInvitation;

  /// No description provided for @addToZtCalendar.
  ///
  /// In en, this message translates to:
  /// **'Add to ZT Calendar'**
  String get addToZtCalendar;

  /// No description provided for @itIsntInYourCalendar.
  ///
  /// In en, this message translates to:
  /// **'It isn\'t in your calendar.'**
  String get itIsntInYourCalendar;

  /// No description provided for @theOrganizerCancelledItRemove.
  ///
  /// In en, this message translates to:
  /// **'The organizer cancelled it. Remove it from your calendar?'**
  String get theOrganizerCancelledItRemove;

  /// No description provided for @toReplyAnswerTheOrganizer.
  ///
  /// In en, this message translates to:
  /// **'To reply, answer the organizer from your mail app.'**
  String get toReplyAnswerTheOrganizer;

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// No description provided for @update.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get update;

  /// No description provided for @calendarColour.
  ///
  /// In en, this message translates to:
  /// **'Calendar colour'**
  String get calendarColour;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @colour.
  ///
  /// In en, this message translates to:
  /// **'Colour'**
  String get colour;

  /// No description provided for @searchZtContacts.
  ///
  /// In en, this message translates to:
  /// **'Search ZT Contacts'**
  String get searchZtContacts;

  /// No description provided for @contactsYouKeepInZt.
  ///
  /// In en, this message translates to:
  /// **'Contacts you keep in ZT Contacts show here.'**
  String get contactsYouKeepInZt;

  /// No description provided for @eventNotes.
  ///
  /// In en, this message translates to:
  /// **'Event notes'**
  String get eventNotes;

  /// No description provided for @linkANote.
  ///
  /// In en, this message translates to:
  /// **'Link a note'**
  String get linkANote;

  /// No description provided for @newNoteForThisEvent.
  ///
  /// In en, this message translates to:
  /// **'New note for this event'**
  String get newNoteForThisEvent;

  /// No description provided for @createdInZtNotesEncrypted.
  ///
  /// In en, this message translates to:
  /// **'Created in ZT Notes, encrypted like your other notes'**
  String get createdInZtNotesEncrypted;

  /// No description provided for @searchZtNotes.
  ///
  /// In en, this message translates to:
  /// **'Search ZT Notes'**
  String get searchZtNotes;

  /// No description provided for @yourZtNotesNotesShow.
  ///
  /// In en, this message translates to:
  /// **'Your ZT Notes notes show here.'**
  String get yourZtNotesNotesShow;

  /// No description provided for @thisNoteIsEmpty.
  ///
  /// In en, this message translates to:
  /// **'This note is empty.'**
  String get thisNoteIsEmpty;

  /// No description provided for @editItInZtNotes.
  ///
  /// In en, this message translates to:
  /// **'Edit it in ZT Notes.'**
  String get editItInZtNotes;

  /// No description provided for @openZtNotes.
  ///
  /// In en, this message translates to:
  /// **'Open ZT Notes'**
  String get openZtNotes;

  /// No description provided for @aRepeatingTaskTickIt.
  ///
  /// In en, this message translates to:
  /// **'A repeating task: tick it off in ZT Tasks, which moves it to its next date.'**
  String get aRepeatingTaskTickIt;

  /// No description provided for @openZtTasks.
  ///
  /// In en, this message translates to:
  /// **'Open ZT Tasks'**
  String get openZtTasks;

  /// No description provided for @call.
  ///
  /// In en, this message translates to:
  /// **'Call'**
  String get call;

  /// No description provided for @message.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get message;

  /// No description provided for @savedInZtTasksOn.
  ///
  /// In en, this message translates to:
  /// **'Saved in ZT Tasks on all your devices'**
  String get savedInZtTasksOn;

  /// No description provided for @move.
  ///
  /// In en, this message translates to:
  /// **'Move'**
  String get move;

  /// No description provided for @undo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undo;

  /// No description provided for @showOnThisPhone.
  ///
  /// In en, this message translates to:
  /// **'Show on this phone?'**
  String get showOnThisPhone;

  /// No description provided for @turnOn.
  ///
  /// In en, this message translates to:
  /// **'Turn on'**
  String get turnOn;

  /// No description provided for @calendarPermissionIsNeededFor.
  ///
  /// In en, this message translates to:
  /// **'Calendar permission is needed for this.'**
  String get calendarPermissionIsNeededFor;

  /// No description provided for @showOnThisPhoneX.
  ///
  /// In en, this message translates to:
  /// **'Show on this phone'**
  String get showOnThisPhoneX;

  /// No description provided for @letsWearOsAndroidAuto.
  ///
  /// In en, this message translates to:
  /// **'Lets Wear OS, Android Auto, the clock\'s alarm screen and other calendar apps show these events. They are copied without encryption into a calendar on this phone only.'**
  String get letsWearOsAndroidAuto;

  /// No description provided for @signInFirst.
  ///
  /// In en, this message translates to:
  /// **'Sign in first.'**
  String get signInFirst;

  /// No description provided for @onlyAvailableOnAndroid.
  ///
  /// In en, this message translates to:
  /// **'Only available on Android.'**
  String get onlyAvailableOnAndroid;

  /// No description provided for @taskAddedToZtTasks.
  ///
  /// In en, this message translates to:
  /// **'Task added to ZT Tasks'**
  String get taskAddedToZtTasks;

  /// No description provided for @task.
  ///
  /// In en, this message translates to:
  /// **'Task'**
  String get task;

  /// No description provided for @payRentFriday.
  ///
  /// In en, this message translates to:
  /// **'Pay rent Friday'**
  String get payRentFriday;

  /// No description provided for @lunchWithDanaFri1pm.
  ///
  /// In en, this message translates to:
  /// **'Lunch with Dana Fri 1pm'**
  String get lunchWithDanaFri1pm;

  /// No description provided for @addedToZtTasksWith.
  ///
  /// In en, this message translates to:
  /// **'Added to ZT Tasks with its due date'**
  String get addedToZtTasksWith;

  /// No description provided for @tryDentistTomorrow930.
  ///
  /// In en, this message translates to:
  /// **'Try \"Dentist tomorrow 9:30 at Smile Clinic\" or \"מחר ב-13:00 פגישה\"'**
  String get tryDentistTomorrow930;

  /// No description provided for @addATitle.
  ///
  /// In en, this message translates to:
  /// **'(Add a title)'**
  String get addATitle;

  /// No description provided for @moreOptions.
  ///
  /// In en, this message translates to:
  /// **'More options'**
  String get moreOptions;

  /// No description provided for @addTask.
  ///
  /// In en, this message translates to:
  /// **'Add task'**
  String get addTask;

  /// No description provided for @savedInZtTasksEncrypted.
  ///
  /// In en, this message translates to:
  /// **'Saved in ZT Tasks, encrypted like everything else.'**
  String get savedInZtTasksEncrypted;

  /// No description provided for @repeat.
  ///
  /// In en, this message translates to:
  /// **'Repeat'**
  String get repeat;

  /// No description provided for @custom.
  ///
  /// In en, this message translates to:
  /// **'Custom…'**
  String get custom;

  /// No description provided for @customRepeat.
  ///
  /// In en, this message translates to:
  /// **'Custom repeat'**
  String get customRepeat;

  /// No description provided for @repeatsEvery.
  ///
  /// In en, this message translates to:
  /// **'Repeats every'**
  String get repeatsEvery;

  /// No description provided for @on.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get on;

  /// No description provided for @ends.
  ///
  /// In en, this message translates to:
  /// **'Ends'**
  String get ends;

  /// No description provided for @never.
  ///
  /// In en, this message translates to:
  /// **'Never'**
  String get never;

  /// No description provided for @showEarlier.
  ///
  /// In en, this message translates to:
  /// **'Show earlier'**
  String get showEarlier;

  /// No description provided for @nothingPlannedTapToAdd.
  ///
  /// In en, this message translates to:
  /// **'Nothing planned. Tap + to add an event.'**
  String get nothingPlannedTapToAdd;

  /// No description provided for @nothingToday.
  ///
  /// In en, this message translates to:
  /// **'Nothing today'**
  String get nothingToday;

  /// No description provided for @searchEvents.
  ///
  /// In en, this message translates to:
  /// **'Search events'**
  String get searchEvents;

  /// No description provided for @noEventsFound.
  ///
  /// In en, this message translates to:
  /// **'No events found'**
  String get noEventsFound;

  /// No description provided for @addRenameRecolourOrHide.
  ///
  /// In en, this message translates to:
  /// **'Add, rename, recolour or hide'**
  String get addRenameRecolourOrHide;

  /// No description provided for @holidaysAndSubscribedCalendars.
  ///
  /// In en, this message translates to:
  /// **'Holidays and subscribed calendars'**
  String get holidaysAndSubscribedCalendars;

  /// No description provided for @publicHolidaysSchoolOrTeam.
  ///
  /// In en, this message translates to:
  /// **'Public holidays, school or team calendars'**
  String get publicHolidaysSchoolOrTeam;

  /// No description provided for @offForYourWatchCar.
  ///
  /// In en, this message translates to:
  /// **'Off. For your watch, car and other calendar apps'**
  String get offForYourWatchCar;

  /// No description provided for @onForSomeCalendarsCopied.
  ///
  /// In en, this message translates to:
  /// **'On for some calendars, copied to Android\'s calendar'**
  String get onForSomeCalendarsCopied;

  /// No description provided for @startOfTheWeek.
  ///
  /// In en, this message translates to:
  /// **'Start of the week'**
  String get startOfTheWeek;

  /// No description provided for @defaultEventLength.
  ///
  /// In en, this message translates to:
  /// **'Default event length'**
  String get defaultEventLength;

  /// No description provided for @defaultReminder.
  ///
  /// In en, this message translates to:
  /// **'Default reminder'**
  String get defaultReminder;

  /// No description provided for @none.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get none;

  /// No description provided for @defaultAllDayReminder.
  ///
  /// In en, this message translates to:
  /// **'Default all-day reminder'**
  String get defaultAllDayReminder;

  /// No description provided for @eventTitlesInReminders.
  ///
  /// In en, this message translates to:
  /// **'Event titles in reminders'**
  String get eventTitlesInReminders;

  /// No description provided for @offRemindersOnlySayEvent.
  ///
  /// In en, this message translates to:
  /// **'Off: reminders only say \"Event\". Titles are handed to the phone so they can show while Calendar is locked.'**
  String get offRemindersOnlySayEvent;

  /// No description provided for @showDetailsOnTheHome.
  ///
  /// In en, this message translates to:
  /// **'Show details on the home screen'**
  String get showDetailsOnTheHome;

  /// No description provided for @offTheUpNextWidget.
  ///
  /// In en, this message translates to:
  /// **'Off: the widgets show only times, and which days have events. On: event and task titles are stored unencrypted on this phone for the home screen.'**
  String get offTheUpNextWidget;

  /// No description provided for @showTasksFromZtTasks.
  ///
  /// In en, this message translates to:
  /// **'Show tasks from ZT Tasks'**
  String get showTasksFromZtTasks;

  /// No description provided for @tasksWithADueDate.
  ///
  /// In en, this message translates to:
  /// **'Tasks with a due date. Tick them off here'**
  String get tasksWithADueDate;

  /// No description provided for @showCompletedTasks.
  ///
  /// In en, this message translates to:
  /// **'Show completed tasks'**
  String get showCompletedTasks;

  /// No description provided for @showBirthdaysFromZtContacts.
  ///
  /// In en, this message translates to:
  /// **'Show birthdays from ZT Contacts'**
  String get showBirthdaysFromZtContacts;

  /// No description provided for @refreshNotesTasksAndContacts.
  ///
  /// In en, this message translates to:
  /// **'Refresh notes, tasks and contacts'**
  String get refreshNotesTasksAndContacts;

  /// No description provided for @calendarKeepsItsOwnEncrypted.
  ///
  /// In en, this message translates to:
  /// **'Calendar keeps its own encrypted copy of them on this phone'**
  String get calendarKeepsItsOwnEncrypted;

  /// No description provided for @upToDate.
  ///
  /// In en, this message translates to:
  /// **'Up to date'**
  String get upToDate;

  /// No description provided for @importFromGoogleCalendarOr.
  ///
  /// In en, this message translates to:
  /// **'Import from Google Calendar or .ics'**
  String get importFromGoogleCalendarOr;

  /// No description provided for @anIcsFileOrThe.
  ///
  /// In en, this message translates to:
  /// **'An .ics file, or the Google Takeout .zip with your calendars'**
  String get anIcsFileOrThe;

  /// No description provided for @exportAllEventsIcs.
  ///
  /// In en, this message translates to:
  /// **'Export all events (.ics)'**
  String get exportAllEventsIcs;

  /// No description provided for @unencryptedFileForOtherCalendar.
  ///
  /// In en, this message translates to:
  /// **'Unencrypted file, for other calendar apps'**
  String get unencryptedFileForOtherCalendar;

  /// No description provided for @exportEvents.
  ///
  /// In en, this message translates to:
  /// **'Export events?'**
  String get exportEvents;

  /// No description provided for @theIcsFileIsNot.
  ///
  /// In en, this message translates to:
  /// **'The .ics file is not encrypted. Anyone who gets it can read your events. Share it only with apps you trust.'**
  String get theIcsFileIsNot;

  /// No description provided for @exportLabel.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get exportLabel;

  /// No description provided for @importEvents.
  ///
  /// In en, this message translates to:
  /// **'Import events'**
  String get importEvents;

  /// No description provided for @fromGoogleCalendarGoTo.
  ///
  /// In en, this message translates to:
  /// **'From Google Calendar: go to takeout.google.com, choose only \"Calendar\", download the .zip and pick it here. Every calendar in it is added, and importing the same file again skips events you already have.\n\nFrom other apps: export an .ics file and pick it.'**
  String get fromGoogleCalendarGoTo;

  /// No description provided for @chooseFile.
  ///
  /// In en, this message translates to:
  /// **'Choose file'**
  String get chooseFile;

  /// No description provided for @chooseAnIcsOrZip.
  ///
  /// In en, this message translates to:
  /// **'Choose an .ics or .zip file'**
  String get chooseAnIcsOrZip;

  /// No description provided for @subscribeToACalendar.
  ///
  /// In en, this message translates to:
  /// **'Subscribe to a calendar'**
  String get subscribeToACalendar;

  /// No description provided for @calendarDownloadsItFromThat.
  ///
  /// In en, this message translates to:
  /// **'Calendar downloads it from that address (the site sees a download from your phone, nothing about your account) and keeps an encrypted copy, refreshed every few hours while Calendar is open. Its events are read-only.'**
  String get calendarDownloadsItFromThat;

  /// No description provided for @subscribe.
  ///
  /// In en, this message translates to:
  /// **'Subscribe'**
  String get subscribe;

  /// No description provided for @holidaysAndSubscriptions.
  ///
  /// In en, this message translates to:
  /// **'Holidays and subscriptions'**
  String get holidaysAndSubscriptions;

  /// No description provided for @subscribeByLink.
  ///
  /// In en, this message translates to:
  /// **'Subscribe by link'**
  String get subscribeByLink;

  /// No description provided for @anyIcsOrWebcalLink.
  ///
  /// In en, this message translates to:
  /// **'Any .ics or webcal link: school, team, sports'**
  String get anyIcsOrWebcalLink;

  /// No description provided for @publicHolidaysComeFromGoogles.
  ///
  /// In en, this message translates to:
  /// **'Public holidays come from Google\'s public holiday calendars, downloaded like any web page: no Google account is used and nothing about you is sent.'**
  String get publicHolidaysComeFromGoogles;

  /// No description provided for @downloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading…'**
  String get downloading;

  /// No description provided for @refreshNow.
  ///
  /// In en, this message translates to:
  /// **'Refresh now'**
  String get refreshNow;

  /// No description provided for @unsubscribe.
  ///
  /// In en, this message translates to:
  /// **'Unsubscribe'**
  String get unsubscribe;

  /// No description provided for @searchCityOrRegion.
  ///
  /// In en, this message translates to:
  /// **'Search city or region'**
  String get searchCityOrRegion;

  /// No description provided for @phonesTimeZone.
  ///
  /// In en, this message translates to:
  /// **'Phone\'s time zone'**
  String get phonesTimeZone;

  /// No description provided for @dragToChangeTheEnd.
  ///
  /// In en, this message translates to:
  /// **'Drag to change the end time'**
  String get dragToChangeTheEnd;

  /// No description provided for @birthday.
  ///
  /// In en, this message translates to:
  /// **'Birthday'**
  String get birthday;

  /// No description provided for @upNext.
  ///
  /// In en, this message translates to:
  /// **'Up next'**
  String get upNext;

  /// No description provided for @nothingComingUp.
  ///
  /// In en, this message translates to:
  /// **'Nothing coming up'**
  String get nothingComingUp;

  /// No description provided for @openZtCalendarToSee.
  ///
  /// In en, this message translates to:
  /// **'Open ZT Calendar to see what\'s next'**
  String get openZtCalendarToSee;

  /// No description provided for @tomorrow.
  ///
  /// In en, this message translates to:
  /// **'Tomorrow'**
  String get tomorrow;

  /// No description provided for @yesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get yesterday;

  /// No description provided for @spanTo.
  ///
  /// In en, this message translates to:
  /// **'{from} to {to}'**
  String spanTo(String from, String to);

  /// No description provided for @reminderOnTheDay.
  ///
  /// In en, this message translates to:
  /// **'On the day at 9:00'**
  String get reminderOnTheDay;

  /// No description provided for @reminderDaysBeforeAt9.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{The day before at 9:00} other{{count} days before at 9:00}}'**
  String reminderDaysBeforeAt9(int count);

  /// No description provided for @reminderAtStart.
  ///
  /// In en, this message translates to:
  /// **'At the start'**
  String get reminderAtStart;

  /// No description provided for @reminderWeeksBefore.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 week before} other{{count} weeks before}}'**
  String reminderWeeksBefore(int count);

  /// No description provided for @reminderDaysBefore.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 day before} other{{count} days before}}'**
  String reminderDaysBefore(int count);

  /// No description provided for @reminderHoursBefore.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 hour before} other{{count} hours before}}'**
  String reminderHoursBefore(int count);

  /// No description provided for @reminderMinutesBefore.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 minute before} other{{count} minutes before}}'**
  String reminderMinutesBefore(int count);

  /// No description provided for @ordFirst.
  ///
  /// In en, this message translates to:
  /// **'first'**
  String get ordFirst;

  /// No description provided for @ordSecond.
  ///
  /// In en, this message translates to:
  /// **'second'**
  String get ordSecond;

  /// No description provided for @ordThird.
  ///
  /// In en, this message translates to:
  /// **'third'**
  String get ordThird;

  /// No description provided for @ordFourth.
  ///
  /// In en, this message translates to:
  /// **'fourth'**
  String get ordFourth;

  /// No description provided for @ordFifth.
  ///
  /// In en, this message translates to:
  /// **'fifth'**
  String get ordFifth;

  /// No description provided for @ordLast.
  ///
  /// In en, this message translates to:
  /// **'last'**
  String get ordLast;

  /// No description provided for @ordSecondToLast.
  ///
  /// In en, this message translates to:
  /// **'second to last'**
  String get ordSecondToLast;

  /// No description provided for @onTheNthWeekday.
  ///
  /// In en, this message translates to:
  /// **'On the {ordinal} {weekday}'**
  String onTheNthWeekday(String ordinal, String weekday);

  /// No description provided for @doesNotRepeat.
  ///
  /// In en, this message translates to:
  /// **'Does not repeat'**
  String get doesNotRepeat;

  /// No description provided for @everyNDays.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Every day} other{Every {count} days}}'**
  String everyNDays(int count);

  /// No description provided for @everyNWeeks.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Every week} other{Every {count} weeks}}'**
  String everyNWeeks(int count);

  /// No description provided for @everyNMonths.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Every month} other{Every {count} months}}'**
  String everyNMonths(int count);

  /// No description provided for @everyNYears.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Every year} other{Every {count} years}}'**
  String everyNYears(int count);

  /// No description provided for @everyWeekday.
  ///
  /// In en, this message translates to:
  /// **'Every weekday'**
  String get everyWeekday;

  /// No description provided for @ruleOnWeekdays.
  ///
  /// In en, this message translates to:
  /// **'{rule} on weekdays'**
  String ruleOnWeekdays(String rule);

  /// No description provided for @ruleOnEveryDay.
  ///
  /// In en, this message translates to:
  /// **'{rule} on every day'**
  String ruleOnEveryDay(String rule);

  /// No description provided for @listAnd.
  ///
  /// In en, this message translates to:
  /// **'{items} and {last}'**
  String listAnd(String items, String last);

  /// No description provided for @ruleOnDays.
  ///
  /// In en, this message translates to:
  /// **'{rule} on {days}'**
  String ruleOnDays(String rule, String days);

  /// No description provided for @ruleOnNthWeekday.
  ///
  /// In en, this message translates to:
  /// **'{rule} on the {ordinal} {weekday}'**
  String ruleOnNthWeekday(String rule, String ordinal, String weekday);

  /// No description provided for @ruleOnLastDay.
  ///
  /// In en, this message translates to:
  /// **'{rule} on the last day'**
  String ruleOnLastDay(String rule);

  /// No description provided for @ruleOnDay.
  ///
  /// In en, this message translates to:
  /// **'{rule} on day {day}'**
  String ruleOnDay(String rule, int day);

  /// No description provided for @ruleOnDate.
  ///
  /// In en, this message translates to:
  /// **'{rule} on {date}'**
  String ruleOnDate(String rule, String date);

  /// No description provided for @ruleTimes.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{, once} other{, {count} times}}'**
  String ruleTimes(int count);

  /// No description provided for @ruleUntil.
  ///
  /// In en, this message translates to:
  /// **', until {date}'**
  String ruleUntil(String date);

  /// No description provided for @personal.
  ///
  /// In en, this message translates to:
  /// **'Personal'**
  String get personal;

  /// No description provided for @couldNotOpenFile.
  ///
  /// In en, this message translates to:
  /// **'Could not open the file: {error}'**
  String couldNotOpenFile(String error);

  /// No description provided for @nEvents.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 event} other{{count} events}}'**
  String nEvents(int count);

  /// No description provided for @subscribedReadOnly.
  ///
  /// In en, this message translates to:
  /// **'subscribed, read-only'**
  String get subscribedReadOnly;

  /// No description provided for @hiddenLabel.
  ///
  /// In en, this message translates to:
  /// **'hidden'**
  String get hiddenLabel;

  /// No description provided for @unsubscribeFrom.
  ///
  /// In en, this message translates to:
  /// **'Unsubscribe from \"{name}\"?'**
  String unsubscribeFrom(String name);

  /// No description provided for @deleteNamed.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{name}\"?'**
  String deleteNamed(String name);

  /// No description provided for @calendarDefaultName.
  ///
  /// In en, this message translates to:
  /// **'Calendar'**
  String get calendarDefaultName;

  /// No description provided for @allDayLower.
  ///
  /// In en, this message translates to:
  /// **'all day'**
  String get allDayLower;

  /// No description provided for @untilTime.
  ///
  /// In en, this message translates to:
  /// **'Until {time}'**
  String untilTime(String time);

  /// No description provided for @dueAt.
  ///
  /// In en, this message translates to:
  /// **'Due {when}'**
  String dueAt(String when);

  /// No description provided for @toDate.
  ///
  /// In en, this message translates to:
  /// **'to {date}'**
  String toDate(String date);

  /// No description provided for @timeInZone.
  ///
  /// In en, this message translates to:
  /// **'{span} in {city} ({offset})'**
  String timeInZone(String span, String city, String offset);

  /// No description provided for @nGuests.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 guest} other{{count} guests}}'**
  String nGuests(int count);

  /// No description provided for @callName.
  ///
  /// In en, this message translates to:
  /// **'Call {name}'**
  String callName(String name);

  /// No description provided for @actionRepeatingEvent.
  ///
  /// In en, this message translates to:
  /// **'{action} repeating event'**
  String actionRepeatingEvent(String action);

  /// No description provided for @couldNotSave.
  ///
  /// In en, this message translates to:
  /// **'Could not save: {error}'**
  String couldNotSave(String error);

  /// No description provided for @couldNotAttach.
  ///
  /// In en, this message translates to:
  /// **'Could not attach the file: {error}'**
  String couldNotAttach(String error);

  /// No description provided for @phoneTimeZoneOffset.
  ///
  /// In en, this message translates to:
  /// **'Phone\'s time zone ({offset})'**
  String phoneTimeZoneOffset(String offset);

  /// No description provided for @yourTime.
  ///
  /// In en, this message translates to:
  /// **'Your time: {time}'**
  String yourTime(String time);

  /// No description provided for @aboutMinutes.
  ///
  /// In en, this message translates to:
  /// **'About {count} minutes'**
  String aboutMinutes(int count);

  /// No description provided for @runningLateText.
  ///
  /// In en, this message translates to:
  /// **'Running about {count} minutes late for {title}. Sorry!'**
  String runningLateText(int count, String title);

  /// No description provided for @inviteEmailWarning.
  ///
  /// In en, this message translates to:
  /// **'Your mail app opens with an invitation to {names}. Email isn\'t end-to-end encrypted: the event\'s title, time, place and description go in it. Attachments and linked notes don\'t.'**
  String inviteEmailWarning(String names);

  /// No description provided for @inviteSubject.
  ///
  /// In en, this message translates to:
  /// **'Invitation: {title} ({when})'**
  String inviteSubject(String title, String when);

  /// No description provided for @inviteYoureInvited.
  ///
  /// In en, this message translates to:
  /// **'You\'re invited: {title}'**
  String inviteYoureInvited(String title);

  /// No description provided for @inviteWhen.
  ///
  /// In en, this message translates to:
  /// **'When: {when}'**
  String inviteWhen(String when);

  /// No description provided for @inviteWhere.
  ///
  /// In en, this message translates to:
  /// **'Where: {where}'**
  String inviteWhere(String where);

  /// No description provided for @inviteJoin.
  ///
  /// In en, this message translates to:
  /// **'Join: {link}'**
  String inviteJoin(String link);

  /// No description provided for @removedCancelled.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Removed 1 cancelled event} other{Removed {count} cancelled events}}'**
  String removedCancelled(int count);

  /// No description provided for @addedNEvents.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Added 1 event} other{Added {count} events}}'**
  String addedNEvents(int count);

  /// No description provided for @couldNotAddIt.
  ///
  /// In en, this message translates to:
  /// **'Could not add it: {error}'**
  String couldNotAddIt(String error);

  /// No description provided for @andNMore.
  ///
  /// In en, this message translates to:
  /// **'and {count} more'**
  String andNMore(int count);

  /// No description provided for @openApp.
  ///
  /// In en, this message translates to:
  /// **'Open {app}'**
  String openApp(String app);

  /// No description provided for @couldNotCreateNote.
  ///
  /// In en, this message translates to:
  /// **'Could not create the note: {error}'**
  String couldNotCreateNote(String error);

  /// No description provided for @turnsAge.
  ///
  /// In en, this message translates to:
  /// **'turns {age}'**
  String turnsAge(int age);

  /// No description provided for @couldNotUpdateTask.
  ///
  /// In en, this message translates to:
  /// **'Could not update the task: {error}'**
  String couldNotUpdateTask(String error);

  /// No description provided for @movedTo.
  ///
  /// In en, this message translates to:
  /// **'Moved to {when}'**
  String movedTo(String when);

  /// No description provided for @couldNotMove.
  ///
  /// In en, this message translates to:
  /// **'Could not move it: {error}'**
  String couldNotMove(String error);

  /// No description provided for @addedTitle.
  ///
  /// In en, this message translates to:
  /// **'Added \"{title}\"'**
  String addedTitle(String title);

  /// No description provided for @onDayN.
  ///
  /// In en, this message translates to:
  /// **'On day {day}'**
  String onDayN(int day);

  /// No description provided for @endsOn.
  ///
  /// In en, this message translates to:
  /// **'On '**
  String get endsOn;

  /// No description provided for @endsAfter.
  ///
  /// In en, this message translates to:
  /// **'After '**
  String get endsAfter;

  /// No description provided for @timesSuffix.
  ///
  /// In en, this message translates to:
  /// **' {count, plural, =1{time} other{times}}'**
  String timesSuffix(int count);

  /// No description provided for @couldNotLoadEvents.
  ///
  /// In en, this message translates to:
  /// **'Could not load events: {error}'**
  String couldNotLoadEvents(String error);

  /// No description provided for @showUntil.
  ///
  /// In en, this message translates to:
  /// **'Show until {date}'**
  String showUntil(String date);

  /// No description provided for @likeYourRegionDay.
  ///
  /// In en, this message translates to:
  /// **'Like your region ({day})'**
  String likeYourRegionDay(String day);

  /// No description provided for @likeYourRegion.
  ///
  /// In en, this message translates to:
  /// **'Like your region'**
  String get likeYourRegion;

  /// No description provided for @nMinutes.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 minute} other{{count} minutes}}'**
  String nMinutes(int count);

  /// No description provided for @nHours.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 hour} other{{count} hours}}'**
  String nHours(int count);

  /// No description provided for @nHoursDecimal.
  ///
  /// In en, this message translates to:
  /// **'{count} hours'**
  String nHoursDecimal(String count);

  /// No description provided for @importedNEvents.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Imported 1 event} other{Imported {count} events}}'**
  String importedNEvents(int count);

  /// No description provided for @intoNewCalendars.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{ into 1 new calendar} other{ into {count} new calendars}}'**
  String intoNewCalendars(int count);

  /// No description provided for @skippedAlreadyHere.
  ///
  /// In en, this message translates to:
  /// **', skipped {count} already here'**
  String skippedAlreadyHere(int count);

  /// No description provided for @couldNotImportFile.
  ///
  /// In en, this message translates to:
  /// **'Could not import that file: {error}'**
  String couldNotImportFile(String error);

  /// No description provided for @downloadingName.
  ///
  /// In en, this message translates to:
  /// **'Downloading {name}…'**
  String downloadingName(String name);

  /// No description provided for @subscribedTo.
  ///
  /// In en, this message translates to:
  /// **'Subscribed to {name}'**
  String subscribedTo(String name);

  /// No description provided for @couldNotSubscribe.
  ///
  /// In en, this message translates to:
  /// **'Could not subscribe: {error}'**
  String couldNotSubscribe(String error);

  /// No description provided for @holidaysOf.
  ///
  /// In en, this message translates to:
  /// **'{name} holidays'**
  String holidaysOf(String name);

  /// No description provided for @lastRefreshFailed.
  ///
  /// In en, this message translates to:
  /// **'Last refresh failed: {error}'**
  String lastRefreshFailed(String error);

  /// No description provided for @followsPhoneZone.
  ///
  /// In en, this message translates to:
  /// **'Follows the phone when you travel ({offset})'**
  String followsPhoneZone(String offset);

  /// No description provided for @birthdayOf.
  ///
  /// In en, this message translates to:
  /// **'{name}\'s birthday'**
  String birthdayOf(String name);

  /// No description provided for @regionIsraelJewishHolidays.
  ///
  /// In en, this message translates to:
  /// **'Israel (Jewish holidays)'**
  String get regionIsraelJewishHolidays;

  /// No description provided for @regionIsraelJewishHolidaysHebrew.
  ///
  /// In en, this message translates to:
  /// **'Israel (Jewish holidays, Hebrew)'**
  String get regionIsraelJewishHolidaysHebrew;

  /// No description provided for @regionUnitedStates.
  ///
  /// In en, this message translates to:
  /// **'United States'**
  String get regionUnitedStates;

  /// No description provided for @regionUnitedKingdom.
  ///
  /// In en, this message translates to:
  /// **'United Kingdom'**
  String get regionUnitedKingdom;

  /// No description provided for @regionCanada.
  ///
  /// In en, this message translates to:
  /// **'Canada'**
  String get regionCanada;

  /// No description provided for @regionAustralia.
  ///
  /// In en, this message translates to:
  /// **'Australia'**
  String get regionAustralia;

  /// No description provided for @regionIreland.
  ///
  /// In en, this message translates to:
  /// **'Ireland'**
  String get regionIreland;

  /// No description provided for @regionGermany.
  ///
  /// In en, this message translates to:
  /// **'Germany'**
  String get regionGermany;

  /// No description provided for @regionFrance.
  ///
  /// In en, this message translates to:
  /// **'France'**
  String get regionFrance;

  /// No description provided for @regionItaly.
  ///
  /// In en, this message translates to:
  /// **'Italy'**
  String get regionItaly;

  /// No description provided for @regionSpain.
  ///
  /// In en, this message translates to:
  /// **'Spain'**
  String get regionSpain;

  /// No description provided for @regionNetherlands.
  ///
  /// In en, this message translates to:
  /// **'Netherlands'**
  String get regionNetherlands;

  /// No description provided for @regionPortugal.
  ///
  /// In en, this message translates to:
  /// **'Portugal'**
  String get regionPortugal;

  /// No description provided for @regionPoland.
  ///
  /// In en, this message translates to:
  /// **'Poland'**
  String get regionPoland;

  /// No description provided for @regionSweden.
  ///
  /// In en, this message translates to:
  /// **'Sweden'**
  String get regionSweden;

  /// No description provided for @regionRussia.
  ///
  /// In en, this message translates to:
  /// **'Russia'**
  String get regionRussia;

  /// No description provided for @regionIndia.
  ///
  /// In en, this message translates to:
  /// **'India'**
  String get regionIndia;

  /// No description provided for @regionJapan.
  ///
  /// In en, this message translates to:
  /// **'Japan'**
  String get regionJapan;

  /// No description provided for @regionChina.
  ///
  /// In en, this message translates to:
  /// **'China'**
  String get regionChina;

  /// No description provided for @regionBrazil.
  ///
  /// In en, this message translates to:
  /// **'Brazil'**
  String get regionBrazil;

  /// No description provided for @regionMexico.
  ///
  /// In en, this message translates to:
  /// **'Mexico'**
  String get regionMexico;

  /// No description provided for @regionSouthAfrica.
  ///
  /// In en, this message translates to:
  /// **'South Africa'**
  String get regionSouthAfrica;

  /// No description provided for @regionChristianHolidays.
  ///
  /// In en, this message translates to:
  /// **'Christian holidays'**
  String get regionChristianHolidays;

  /// No description provided for @regionIslamicHolidays.
  ///
  /// In en, this message translates to:
  /// **'Islamic holidays'**
  String get regionIslamicHolidays;

  /// No description provided for @unitDays.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{day} other{days}}'**
  String unitDays(int count);

  /// No description provided for @unitWeeks.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{week} other{weeks}}'**
  String unitWeeks(int count);

  /// No description provided for @unitMonths.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{month} other{months}}'**
  String unitMonths(int count);

  /// No description provided for @unitYears.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{year} other{years}}'**
  String unitYears(int count);

  /// No description provided for @widgetSignedOut.
  ///
  /// In en, this message translates to:
  /// **'Signed out'**
  String get widgetSignedOut;

  /// No description provided for @widgetMore.
  ///
  /// In en, this message translates to:
  /// **'+{n} more'**
  String widgetMore(String n);

  /// No description provided for @widgetComingUp.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 event coming up} other{{count} events coming up}}'**
  String widgetComingUp(int count);

  /// No description provided for @sharedCalendarUnnamed.
  ///
  /// In en, this message translates to:
  /// **'Shared calendar'**
  String get sharedCalendarUnnamed;

  /// No description provided for @sharedNoAttachments.
  ///
  /// In en, this message translates to:
  /// **'Files can\'t be added to events in a shared calendar: the other members couldn\'t open them.'**
  String get sharedNoAttachments;

  /// No description provided for @sharedAttachmentsDropped.
  ///
  /// In en, this message translates to:
  /// **'This event\'s files stay out of the shared calendar: the other members couldn\'t open them.'**
  String get sharedAttachmentsDropped;

  /// No description provided for @familyCalendarName.
  ///
  /// In en, this message translates to:
  /// **'Family'**
  String get familyCalendarName;

  /// No description provided for @newFamilyCalendar.
  ///
  /// In en, this message translates to:
  /// **'New family calendar'**
  String get newFamilyCalendar;

  /// No description provided for @newSharedCalendar.
  ///
  /// In en, this message translates to:
  /// **'New shared calendar'**
  String get newSharedCalendar;

  /// No description provided for @sharedCalendarIntro.
  ///
  /// In en, this message translates to:
  /// **'Everyone you invite sees and edits its events. Everything is end-to-end encrypted: only your phones can read it.'**
  String get sharedCalendarIntro;

  /// No description provided for @requiredField.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get requiredField;

  /// No description provided for @yourName.
  ///
  /// In en, this message translates to:
  /// **'Your name'**
  String get yourName;

  /// No description provided for @yourNameHint.
  ///
  /// In en, this message translates to:
  /// **'How the other members see you in this calendar.'**
  String get yourNameHint;

  /// No description provided for @create.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// No description provided for @needsInternet.
  ///
  /// In en, this message translates to:
  /// **'This needs an internet connection. Try again when you\'re online.'**
  String get needsInternet;

  /// No description provided for @sharedCalendarGone.
  ///
  /// In en, this message translates to:
  /// **'You\'re no longer in this calendar.'**
  String get sharedCalendarGone;

  /// No description provided for @joinRequest.
  ///
  /// In en, this message translates to:
  /// **'{name} wants to join'**
  String joinRequest(String name);

  /// No description provided for @joinRequestHint.
  ///
  /// In en, this message translates to:
  /// **'Check the code on their phone, then let them in'**
  String get joinRequestHint;

  /// No description provided for @sharedYouAreAdmin.
  ///
  /// In en, this message translates to:
  /// **'Shared · you\'re an admin'**
  String get sharedYouAreAdmin;

  /// No description provided for @sharedYouAreMember.
  ///
  /// In en, this message translates to:
  /// **'Shared · you\'re a member'**
  String get sharedYouAreMember;

  /// No description provided for @myColour.
  ///
  /// In en, this message translates to:
  /// **'My colour'**
  String get myColour;

  /// No description provided for @myColourHint.
  ///
  /// In en, this message translates to:
  /// **'Only on your devices'**
  String get myColourHint;

  /// No description provided for @showInMyCalendar.
  ///
  /// In en, this message translates to:
  /// **'Show in my calendar'**
  String get showInMyCalendar;

  /// No description provided for @nMembers.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 member} other{{count} members}}'**
  String nMembers(int count);

  /// No description provided for @nWaitingToJoin.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 asking to join} other{{count} asking to join}}'**
  String nWaitingToJoin(int count);

  /// No description provided for @memberYou.
  ///
  /// In en, this message translates to:
  /// **'{name} (you)'**
  String memberYou(String name);

  /// No description provided for @roleAdmin.
  ///
  /// In en, this message translates to:
  /// **'Admin'**
  String get roleAdmin;

  /// No description provided for @roleMember.
  ///
  /// In en, this message translates to:
  /// **'Member'**
  String get roleMember;

  /// No description provided for @roleAdminHint.
  ///
  /// In en, this message translates to:
  /// **'Admins also invite and remove people, and rename the calendar.'**
  String get roleAdminHint;

  /// No description provided for @roleMemberHint.
  ///
  /// In en, this message translates to:
  /// **'Members see, add and change events.'**
  String get roleMemberHint;

  /// No description provided for @memberOptions.
  ///
  /// In en, this message translates to:
  /// **'Member options'**
  String get memberOptions;

  /// No description provided for @makeMember.
  ///
  /// In en, this message translates to:
  /// **'Make a member'**
  String get makeMember;

  /// No description provided for @makeAdmin.
  ///
  /// In en, this message translates to:
  /// **'Make an admin'**
  String get makeAdmin;

  /// No description provided for @invitePeople.
  ///
  /// In en, this message translates to:
  /// **'Invite people'**
  String get invitePeople;

  /// No description provided for @sharedPrivacyNote.
  ///
  /// In en, this message translates to:
  /// **'Events here are encrypted with a key only the members\' phones hold. The server sees that this calendar exists and who is in it, never its name or events. Files and linked notes stay private to whoever added them.'**
  String get sharedPrivacyNote;

  /// No description provided for @leaveCalendar.
  ///
  /// In en, this message translates to:
  /// **'Leave calendar'**
  String get leaveCalendar;

  /// No description provided for @deleteForEveryone.
  ///
  /// In en, this message translates to:
  /// **'Delete for everyone'**
  String get deleteForEveryone;

  /// No description provided for @sharedRenameHint.
  ///
  /// In en, this message translates to:
  /// **'The name and colour change for every member, unless they picked their own colour.'**
  String get sharedRenameHint;

  /// No description provided for @removeMemberTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove {name}?'**
  String removeMemberTitle(String name);

  /// No description provided for @removeMemberBody.
  ///
  /// In en, this message translates to:
  /// **'They lose access, and the calendar moves to a new key so they can\'t read anything added from now on.'**
  String get removeMemberBody;

  /// No description provided for @leaveCalendarTitle.
  ///
  /// In en, this message translates to:
  /// **'Leave {name}?'**
  String leaveCalendarTitle(String name);

  /// No description provided for @leaveCalendarBody.
  ///
  /// In en, this message translates to:
  /// **'Its events disappear from your devices. Someone has to invite you again to come back.'**
  String get leaveCalendarBody;

  /// No description provided for @deleteForEveryoneTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete {name} for everyone?'**
  String deleteForEveryoneTitle(String name);

  /// No description provided for @deleteForEveryoneBody.
  ///
  /// In en, this message translates to:
  /// **'The calendar and all its events are deleted for every member. This can\'t be undone.'**
  String get deleteForEveryoneBody;

  /// No description provided for @waitingToJoin.
  ///
  /// In en, this message translates to:
  /// **'Waiting to join'**
  String get waitingToJoin;

  /// No description provided for @waitingToJoinShort.
  ///
  /// In en, this message translates to:
  /// **'An admin still has to let you in'**
  String get waitingToJoinShort;

  /// No description provided for @waitingToJoinBody.
  ///
  /// In en, this message translates to:
  /// **'Show this code to the person who invited you. Once they see the same code and let you in, the calendar appears here.'**
  String get waitingToJoinBody;

  /// No description provided for @cancelJoin.
  ///
  /// In en, this message translates to:
  /// **'Cancel joining'**
  String get cancelJoin;

  /// No description provided for @confirmJoinTitle.
  ///
  /// In en, this message translates to:
  /// **'Let {name} into {calendar}?'**
  String confirmJoinTitle(String name, String calendar);

  /// No description provided for @confirmJoinBody.
  ///
  /// In en, this message translates to:
  /// **'Their phone shows a code. Let them in only if it\'s exactly this one:'**
  String get confirmJoinBody;

  /// No description provided for @codesDiffer.
  ///
  /// In en, this message translates to:
  /// **'Codes differ'**
  String get codesDiffer;

  /// No description provided for @later.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get later;

  /// No description provided for @codesMatch.
  ///
  /// In en, this message translates to:
  /// **'Codes match'**
  String get codesMatch;

  /// No description provided for @joinedCalendar.
  ///
  /// In en, this message translates to:
  /// **'{name} joined'**
  String joinedCalendar(String name);

  /// No description provided for @inviteTo.
  ///
  /// In en, this message translates to:
  /// **'Invite to {name}'**
  String inviteTo(String name);

  /// No description provided for @inviteIntro.
  ///
  /// In en, this message translates to:
  /// **'Make a one-time invite for one person. Send the link, or let them scan the code.'**
  String get inviteIntro;

  /// No description provided for @createInvite.
  ///
  /// In en, this message translates to:
  /// **'Create invite'**
  String get createInvite;

  /// No description provided for @inviteReady.
  ///
  /// In en, this message translates to:
  /// **'Scan this with ZT Calendar on their phone, or send them the link.'**
  String get inviteReady;

  /// No description provided for @inviteQr.
  ///
  /// In en, this message translates to:
  /// **'Invite QR code'**
  String get inviteQr;

  /// No description provided for @linkCopied.
  ///
  /// In en, this message translates to:
  /// **'Link copied'**
  String get linkCopied;

  /// No description provided for @copyLink.
  ///
  /// In en, this message translates to:
  /// **'Copy link'**
  String get copyLink;

  /// No description provided for @shareLink.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get shareLink;

  /// No description provided for @inviteMessage.
  ///
  /// In en, this message translates to:
  /// **'Join my calendar \"{name}\" in ZT Calendar: {link}'**
  String inviteMessage(String name, String link);

  /// No description provided for @inviteNextSteps.
  ///
  /// In en, this message translates to:
  /// **'The link works once, for 7 days. When they open it, you\'ll both see a code: let them in only if the codes match.'**
  String get inviteNextSteps;

  /// No description provided for @checkForAnswers.
  ///
  /// In en, this message translates to:
  /// **'Check for answers'**
  String get checkForAnswers;

  /// No description provided for @inviteOtherApp.
  ///
  /// In en, this message translates to:
  /// **'This invite is for another Zero-Trust app.'**
  String get inviteOtherApp;

  /// No description provided for @inviteInvalid.
  ///
  /// In en, this message translates to:
  /// **'That isn\'t a Zero-Trust invite link.'**
  String get inviteInvalid;

  /// No description provided for @inviteUsed.
  ///
  /// In en, this message translates to:
  /// **'This invite was already used, withdrawn or has expired. Ask for a new one.'**
  String get inviteUsed;

  /// No description provided for @joinSharedCalendar.
  ///
  /// In en, this message translates to:
  /// **'Join a shared calendar'**
  String get joinSharedCalendar;

  /// No description provided for @joinSharedCalendarHint.
  ///
  /// In en, this message translates to:
  /// **'With an invite link or QR code'**
  String get joinSharedCalendarHint;

  /// No description provided for @joinCodeTitle.
  ///
  /// In en, this message translates to:
  /// **'Compare this code'**
  String get joinCodeTitle;

  /// No description provided for @joinCodeBody.
  ///
  /// In en, this message translates to:
  /// **'The person who invited you sees a code too. They let you in once both codes match.'**
  String get joinCodeBody;

  /// No description provided for @joinIntro.
  ///
  /// In en, this message translates to:
  /// **'Paste the invite link you got, or scan the QR code on the other phone.'**
  String get joinIntro;

  /// No description provided for @inviteLink.
  ///
  /// In en, this message translates to:
  /// **'Invite link'**
  String get inviteLink;

  /// No description provided for @scanQr.
  ///
  /// In en, this message translates to:
  /// **'Scan QR code'**
  String get scanQr;

  /// No description provided for @join.
  ///
  /// In en, this message translates to:
  /// **'Join'**
  String get join;

  /// No description provided for @newCalendarHint.
  ///
  /// In en, this message translates to:
  /// **'Only for you'**
  String get newCalendarHint;

  /// No description provided for @newSharedCalendarHint.
  ///
  /// In en, this message translates to:
  /// **'With friends, a team or a club'**
  String get newSharedCalendarHint;

  /// No description provided for @newFamilyCalendarHint.
  ///
  /// In en, this message translates to:
  /// **'One calendar for the whole household'**
  String get newFamilyCalendarHint;

  /// No description provided for @myDay.
  ///
  /// In en, this message translates to:
  /// **'My day'**
  String get myDay;

  /// No description provided for @myDayNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get myDayNext;

  /// No description provided for @myDayNow.
  ///
  /// In en, this message translates to:
  /// **'Now'**
  String get myDayNow;

  /// No description provided for @myDayTask.
  ///
  /// In en, this message translates to:
  /// **'Task'**
  String get myDayTask;

  /// No description provided for @myDayNoTasks.
  ///
  /// In en, this message translates to:
  /// **'No tasks due today'**
  String get myDayNoTasks;

  /// No description provided for @myDayTasksDue.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Tasks due today} =1{1 task due today} other{{count} tasks due today}}'**
  String myDayTasksDue(int count);

  /// No description provided for @myDayOverdue.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{+1 overdue} other{+{count} overdue}}'**
  String myDayOverdue(int count);

  /// No description provided for @copy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copy;

  /// No description provided for @copied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get copied;

  /// No description provided for @desktopApps.
  ///
  /// In en, this message translates to:
  /// **'Desktop calendar apps'**
  String get desktopApps;

  /// No description provided for @desktopAppsSubtitleOff.
  ///
  /// In en, this message translates to:
  /// **'Off. Let Thunderbird, Apple Calendar or Evolution read your events over Wi-Fi'**
  String get desktopAppsSubtitleOff;

  /// No description provided for @desktopAppsSubtitleOn.
  ///
  /// In en, this message translates to:
  /// **'On while ZT Calendar is unlocked'**
  String get desktopAppsSubtitleOn;

  /// No description provided for @desktopAppsIntro.
  ///
  /// In en, this message translates to:
  /// **'Your computer\'s calendar app can show your ZT Calendar events, read-only, over your home or office Wi-Fi. The phone serves them itself: nothing goes through a server, and it stops when the app locks.'**
  String get desktopAppsIntro;

  /// No description provided for @desktopAppsSwitch.
  ///
  /// In en, this message translates to:
  /// **'Share with computers on this Wi-Fi'**
  String get desktopAppsSwitch;

  /// No description provided for @desktopAppsRunning.
  ///
  /// In en, this message translates to:
  /// **'On. Computers with the password can read your visible calendars'**
  String get desktopAppsRunning;

  /// No description provided for @desktopAppsStarting.
  ///
  /// In en, this message translates to:
  /// **'Starts when ZT Calendar is unlocked'**
  String get desktopAppsStarting;

  /// No description provided for @desktopAppsOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get desktopAppsOff;

  /// No description provided for @desktopAppsFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t start'**
  String get desktopAppsFailed;

  /// No description provided for @desktopAppsServer.
  ///
  /// In en, this message translates to:
  /// **'Server address (CalDAV)'**
  String get desktopAppsServer;

  /// No description provided for @desktopAppsNoWifi.
  ///
  /// In en, this message translates to:
  /// **'Connect the phone to Wi-Fi to see its address'**
  String get desktopAppsNoWifi;

  /// No description provided for @desktopAppsUser.
  ///
  /// In en, this message translates to:
  /// **'User name'**
  String get desktopAppsUser;

  /// No description provided for @desktopAppsPassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get desktopAppsPassword;

  /// No description provided for @desktopAppsFingerprint.
  ///
  /// In en, this message translates to:
  /// **'Certificate fingerprint (SHA-256)'**
  String get desktopAppsFingerprint;

  /// No description provided for @desktopAppsHowTo.
  ///
  /// In en, this message translates to:
  /// **'In your calendar app, add a CalDAV account (Thunderbird: New Calendar, On the Network; Apple Calendar: Add Account, Other CalDAV, Manual) with this address, user name and password. The app warns that the certificate isn\'t trusted: check that its fingerprint matches the one above, then trust it. The computer and phone must be on the same Wi-Fi, and the computer refreshes while ZT Calendar is open and unlocked.'**
  String get desktopAppsHowTo;

  /// No description provided for @desktopAppsNewPassword.
  ///
  /// In en, this message translates to:
  /// **'Make a new password'**
  String get desktopAppsNewPassword;

  /// No description provided for @desktopAppsNewPasswordHint.
  ///
  /// In en, this message translates to:
  /// **'Computers using the old one lose access'**
  String get desktopAppsNewPasswordHint;

  /// No description provided for @desktopAppsPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Only computers on a local network (home or office Wi-Fi) are answered, only with the password, and only to read. Traffic is encrypted with this phone\'s own certificate. A computer keeps the copy it last read, unencrypted, in its calendar app: turn this on only for computers you trust. Hidden calendars, tasks and birthdays are not shared.'**
  String get desktopAppsPrivacy;

  /// No description provided for @shareBusyTimes.
  ///
  /// In en, this message translates to:
  /// **'Share when I\'m busy'**
  String get shareBusyTimes;

  /// No description provided for @shareBusyTimesHint.
  ///
  /// In en, this message translates to:
  /// **'Members see when you\'re busy in your other calendars (times only, never titles), so Find a time works. Encrypted like the rest of this calendar.'**
  String get shareBusyTimesHint;

  /// No description provided for @findATime.
  ///
  /// In en, this message translates to:
  /// **'Find a time'**
  String get findATime;

  /// No description provided for @findATimeSharing.
  ///
  /// In en, this message translates to:
  /// **'{count} of {total} members share when they\'re busy'**
  String findATimeSharing(int count, int total);

  /// No description provided for @findATimeLength.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min'**
  String findATimeLength(int minutes);

  /// No description provided for @findATimeEvenings.
  ///
  /// In en, this message translates to:
  /// **'Evenings'**
  String get findATimeEvenings;

  /// No description provided for @findATimeWeekends.
  ///
  /// In en, this message translates to:
  /// **'Weekends'**
  String get findATimeWeekends;

  /// No description provided for @findATimeEveryone.
  ///
  /// In en, this message translates to:
  /// **'Free for everyone in the calendar, in the next two weeks. Tap a time to add the event.'**
  String get findATimeEveryone;

  /// No description provided for @findATimeMissing.
  ///
  /// In en, this message translates to:
  /// **'Not counting {names}: they don\'t share when they\'re busy. Tap a time to add the event.'**
  String findATimeMissing(String names);

  /// No description provided for @findATimeNone.
  ///
  /// In en, this message translates to:
  /// **'No time works for everyone in the next two weeks. Try a shorter length, evenings or weekends.'**
  String get findATimeNone;

  /// No description provided for @bookingPages.
  ///
  /// In en, this message translates to:
  /// **'Booking pages'**
  String get bookingPages;

  /// No description provided for @bookingPagesHint.
  ///
  /// In en, this message translates to:
  /// **'Let people book time with you from a link'**
  String get bookingPagesHint;

  /// No description provided for @bookingPagesIntro.
  ///
  /// In en, this message translates to:
  /// **'Share a link and people pick a free time. It goes straight into your calendar.'**
  String get bookingPagesIntro;

  /// No description provided for @bookingPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Visitors see the page\'s title, your name on it, its length and your free times. To offer free times, our server sees when you\'re busy (start and end only, never titles) and when bookings are. Names, emails and notes are encrypted on the visitor\'s device to this page\'s key, so only your phones can read them.'**
  String get bookingPrivacy;

  /// No description provided for @newBookingPage.
  ///
  /// In en, this message translates to:
  /// **'New booking page'**
  String get newBookingPage;

  /// No description provided for @bookingPage.
  ///
  /// In en, this message translates to:
  /// **'Booking page'**
  String get bookingPage;

  /// No description provided for @bookingNoPages.
  ///
  /// In en, this message translates to:
  /// **'No booking pages yet.'**
  String get bookingNoPages;

  /// No description provided for @bookingLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load booking pages: {error}'**
  String bookingLoadFailed(String error);

  /// No description provided for @bookingTitle.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get bookingTitle;

  /// No description provided for @bookingTitleHint.
  ///
  /// In en, this message translates to:
  /// **'For example: 30-minute chat'**
  String get bookingTitleHint;

  /// No description provided for @bookingHostName.
  ///
  /// In en, this message translates to:
  /// **'Your name on the page'**
  String get bookingHostName;

  /// No description provided for @bookingDescription.
  ///
  /// In en, this message translates to:
  /// **'Description (optional)'**
  String get bookingDescription;

  /// No description provided for @bookingLength.
  ///
  /// In en, this message translates to:
  /// **'Length'**
  String get bookingLength;

  /// No description provided for @bookingStep.
  ///
  /// In en, this message translates to:
  /// **'Start times every'**
  String get bookingStep;

  /// No description provided for @bookingBuffer.
  ///
  /// In en, this message translates to:
  /// **'Free time around events'**
  String get bookingBuffer;

  /// No description provided for @bookingNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get bookingNone;

  /// No description provided for @bookingNotice.
  ///
  /// In en, this message translates to:
  /// **'Earliest booking'**
  String get bookingNotice;

  /// No description provided for @bookingNoticeHours.
  ///
  /// In en, this message translates to:
  /// **'{hours, plural, =1{1 hour ahead} other{{hours} hours ahead}}'**
  String bookingNoticeHours(int hours);

  /// No description provided for @bookingNoticeDays.
  ///
  /// In en, this message translates to:
  /// **'{days, plural, =1{1 day ahead} other{{days} days ahead}}'**
  String bookingNoticeDays(int days);

  /// No description provided for @bookingHorizon.
  ///
  /// In en, this message translates to:
  /// **'How far ahead'**
  String get bookingHorizon;

  /// No description provided for @bookingHorizonDays.
  ///
  /// In en, this message translates to:
  /// **'{days} days'**
  String bookingHorizonDays(int days);

  /// No description provided for @bookingCalendar.
  ///
  /// In en, this message translates to:
  /// **'Add bookings to'**
  String get bookingCalendar;

  /// No description provided for @bookingTimeZone.
  ///
  /// In en, this message translates to:
  /// **'Time zone'**
  String get bookingTimeZone;

  /// No description provided for @bookingHours.
  ///
  /// In en, this message translates to:
  /// **'Available hours'**
  String get bookingHours;

  /// No description provided for @bookingUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get bookingUnavailable;

  /// No description provided for @bookingAddHours.
  ///
  /// In en, this message translates to:
  /// **'Add hours'**
  String get bookingAddHours;

  /// No description provided for @bookingActive.
  ///
  /// In en, this message translates to:
  /// **'Taking bookings'**
  String get bookingActive;

  /// No description provided for @bookingPaused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get bookingPaused;

  /// No description provided for @bookingShare.
  ///
  /// In en, this message translates to:
  /// **'Share link'**
  String get bookingShare;

  /// No description provided for @bookingDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete booking page'**
  String get bookingDelete;

  /// No description provided for @bookingDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete this booking page? Its link stops working. Bookings already in your calendar stay there.'**
  String get bookingDeleteConfirm;

  /// No description provided for @bookingUpcoming.
  ///
  /// In en, this message translates to:
  /// **'Upcoming bookings'**
  String get bookingUpcoming;

  /// No description provided for @bookingNoneYet.
  ///
  /// In en, this message translates to:
  /// **'No bookings yet.'**
  String get bookingNoneYet;

  /// No description provided for @bookingAdding.
  ///
  /// In en, this message translates to:
  /// **'Being added to your calendar'**
  String get bookingAdding;

  /// No description provided for @bookingNeedsTitle.
  ///
  /// In en, this message translates to:
  /// **'Give the page a title.'**
  String get bookingNeedsTitle;

  /// No description provided for @bookingNeedsHours.
  ///
  /// In en, this message translates to:
  /// **'Choose at least one day with hours.'**
  String get bookingNeedsHours;

  /// No description provided for @bookingEventTitle.
  ///
  /// In en, this message translates to:
  /// **'{name} ({page})'**
  String bookingEventTitle(String name, String page);

  /// No description provided for @bookingEventFooter.
  ///
  /// In en, this message translates to:
  /// **'Booked on your booking page “{page}”.'**
  String bookingEventFooter(String page);

  /// No description provided for @bookingShareText.
  ///
  /// In en, this message translates to:
  /// **'Book a time with me: {link}'**
  String bookingShareText(String link);

  /// No description provided for @widgetNothingElseToday.
  ///
  /// In en, this message translates to:
  /// **'Nothing else today'**
  String get widgetNothingElseToday;

  /// No description provided for @widgetPreviousMonth.
  ///
  /// In en, this message translates to:
  /// **'Previous month'**
  String get widgetPreviousMonth;

  /// No description provided for @widgetNextMonth.
  ///
  /// In en, this message translates to:
  /// **'Next month'**
  String get widgetNextMonth;

  /// No description provided for @leaveEmptyForCalendarsOwnName.
  ///
  /// In en, this message translates to:
  /// **'Leave empty to use the calendar\'s own name'**
  String get leaveEmptyForCalendarsOwnName;

  /// No description provided for @whereDoIFindTheLink.
  ///
  /// In en, this message translates to:
  /// **'Where do I find the link?'**
  String get whereDoIFindTheLink;

  /// No description provided for @googleOutlookOrIcloud.
  ///
  /// In en, this message translates to:
  /// **'Google Calendar, Outlook or iCloud'**
  String get googleOutlookOrIcloud;

  /// No description provided for @getALinkFromAnotherCalendar.
  ///
  /// In en, this message translates to:
  /// **'Get a link from another calendar'**
  String get getALinkFromAnotherCalendar;

  /// No description provided for @feedHelpGoogleTitle.
  ///
  /// In en, this message translates to:
  /// **'Google Calendar'**
  String get feedHelpGoogleTitle;

  /// No description provided for @feedHelpGoogle.
  ///
  /// In en, this message translates to:
  /// **'On a computer, open calendar.google.com and click the gear, then Settings. Under \"Settings for my calendars\" pick the calendar and open \"Integrate calendar\". Copy \"Secret address in iCal format\". Google updates this link every few hours, so a new event can take a while to appear.'**
  String get feedHelpGoogle;

  /// No description provided for @feedHelpOutlookTitle.
  ///
  /// In en, this message translates to:
  /// **'Outlook.com or Microsoft 365'**
  String get feedHelpOutlookTitle;

  /// No description provided for @feedHelpOutlook.
  ///
  /// In en, this message translates to:
  /// **'In Outlook on the web, open Settings, then Calendar, then Shared calendars. Under \"Publish a calendar\" pick the calendar and \"Can view all details\", click Publish, and copy the ICS link.'**
  String get feedHelpOutlook;

  /// No description provided for @feedHelpIcloudTitle.
  ///
  /// In en, this message translates to:
  /// **'iCloud (Apple)'**
  String get feedHelpIcloudTitle;

  /// No description provided for @feedHelpIcloud.
  ///
  /// In en, this message translates to:
  /// **'On an iPhone, open Calendar and tap Calendars. Tap the info button next to the calendar, turn on \"Public Calendar\" and tap \"Share Link\". Anyone with a public iCloud link can open it.'**
  String get feedHelpIcloud;

  /// No description provided for @feedHelpPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Keep these links private: anyone who has one can see that calendar. ZT Calendar stores the link encrypted and downloads it straight from your phone. Subscribed calendars are read-only here. To move events over for good, export a file from the other app and use Import instead.'**
  String get feedHelpPrivacy;

  /// No description provided for @planner.
  ///
  /// In en, this message translates to:
  /// **'Planner'**
  String get planner;

  /// No description provided for @plannedCalendarName.
  ///
  /// In en, this message translates to:
  /// **'Planned'**
  String get plannedCalendarName;

  /// No description provided for @plannerPartOf.
  ///
  /// In en, this message translates to:
  /// **'{title} ({part} of {total})'**
  String plannerPartOf(String title, int part, int total);

  /// No description provided for @plannerHoursMinutes.
  ///
  /// In en, this message translates to:
  /// **'{hours} h {minutes} min'**
  String plannerHoursMinutes(int hours, int minutes);

  /// No description provided for @plannerReasonEarliest.
  ///
  /// In en, this message translates to:
  /// **'This is the earliest free time in your hours.'**
  String get plannerReasonEarliest;

  /// No description provided for @plannerReasonDeadline.
  ///
  /// In en, this message translates to:
  /// **'Placed here to finish before the due date.'**
  String get plannerReasonDeadline;

  /// No description provided for @plannerReasonLate.
  ///
  /// In en, this message translates to:
  /// **'It doesn\'t fit before the due date. This is the earliest time left.'**
  String get plannerReasonLate;

  /// No description provided for @plannerReasonLocked.
  ///
  /// In en, this message translates to:
  /// **'You locked it at this time.'**
  String get plannerReasonLocked;

  /// No description provided for @plannerReasonDone.
  ///
  /// In en, this message translates to:
  /// **'Marked as done.'**
  String get plannerReasonDone;

  /// No description provided for @plannerNoHours.
  ///
  /// In en, this message translates to:
  /// **'No hours set'**
  String get plannerNoHours;

  /// No description provided for @plannerHoursEndFirst.
  ///
  /// In en, this message translates to:
  /// **'The end has to be after the start.'**
  String get plannerHoursEndFirst;

  /// No description provided for @plannerHoursOverlap.
  ///
  /// In en, this message translates to:
  /// **'These hours overlap other hours on that day.'**
  String get plannerHoursOverlap;

  /// No description provided for @plannerDayOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get plannerDayOff;

  /// No description provided for @plannerTaskFinishedSaved.
  ///
  /// In en, this message translates to:
  /// **'Task finished. Saved in ZT Tasks.'**
  String get plannerTaskFinishedSaved;

  /// No description provided for @plannerBlockGone.
  ///
  /// In en, this message translates to:
  /// **'This block is no longer planned.'**
  String get plannerBlockGone;

  /// No description provided for @plannerBlockPart.
  ///
  /// In en, this message translates to:
  /// **'Part {part} of {total}'**
  String plannerBlockPart(int part, int total);

  /// No description provided for @plannerBlockMoves.
  ///
  /// In en, this message translates to:
  /// **'The Planner moves this block when your calendar changes.'**
  String get plannerBlockMoves;

  /// No description provided for @plannerTaskFinished.
  ///
  /// In en, this message translates to:
  /// **'Task finished'**
  String get plannerTaskFinished;

  /// No description provided for @plannerCouldNotPlan.
  ///
  /// In en, this message translates to:
  /// **'Could not plan: {error}'**
  String plannerCouldNotPlan(String error);

  /// No description provided for @plannerIntroTitle.
  ///
  /// In en, this message translates to:
  /// **'Let Calendar plan your tasks'**
  String get plannerIntroTitle;

  /// No description provided for @plannerIntroBody.
  ///
  /// In en, this message translates to:
  /// **'The Planner takes tasks from ZT Tasks and fits them into the free time around your events. When a meeting moves or a new one arrives, it plans again, and it tells you when a task no longer fits before its due date.'**
  String get plannerIntroBody;

  /// No description provided for @plannerIntroPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Everything is worked out on this phone. Your tasks and events stay end-to-end encrypted, and no AI is involved.'**
  String get plannerIntroPrivacy;

  /// No description provided for @plannerSetUp.
  ///
  /// In en, this message translates to:
  /// **'Set up the Planner'**
  String get plannerSetUp;

  /// No description provided for @plannerNext7Days.
  ///
  /// In en, this message translates to:
  /// **'Next 7 days'**
  String get plannerNext7Days;

  /// No description provided for @plannerWaitingForSync.
  ///
  /// In en, this message translates to:
  /// **'Waiting for your calendar and tasks to finish syncing…'**
  String get plannerWaitingForSync;

  /// No description provided for @plannerRiskNoRoom.
  ///
  /// In en, this message translates to:
  /// **'{amount} doesn\'t fit in the next 4 weeks'**
  String plannerRiskNoRoom(String amount);

  /// No description provided for @plannerRiskLate.
  ///
  /// In en, this message translates to:
  /// **'{amount} is planned after the due date'**
  String plannerRiskLate(String amount);

  /// No description provided for @plannerTasksToPlan.
  ///
  /// In en, this message translates to:
  /// **'Tasks to plan'**
  String get plannerTasksToPlan;

  /// No description provided for @plannerLoadingTasks.
  ///
  /// In en, this message translates to:
  /// **'Loading tasks from ZT Tasks…'**
  String get plannerLoadingTasks;

  /// No description provided for @plannerNoOpenTasks.
  ///
  /// In en, this message translates to:
  /// **'There are no open tasks in ZT Tasks.'**
  String get plannerNoOpenTasks;

  /// No description provided for @plannerNoTasksSwitchedOn.
  ///
  /// In en, this message translates to:
  /// **'No task is switched on yet. Switch on the tasks you want planned.'**
  String get plannerNoTasksSwitchedOn;

  /// No description provided for @plannerOtherTasks.
  ///
  /// In en, this message translates to:
  /// **'Other tasks ({count})'**
  String plannerOtherTasks(int count);

  /// No description provided for @plannerWorkHours.
  ///
  /// In en, this message translates to:
  /// **'Work hours'**
  String get plannerWorkHours;

  /// No description provided for @plannerPersonalHours.
  ///
  /// In en, this message translates to:
  /// **'Personal hours'**
  String get plannerPersonalHours;

  /// No description provided for @plannerWhichTasks.
  ///
  /// In en, this message translates to:
  /// **'Which tasks to plan'**
  String get plannerWhichTasks;

  /// No description provided for @plannerAllTasks.
  ///
  /// In en, this message translates to:
  /// **'All tasks'**
  String get plannerAllTasks;

  /// No description provided for @plannerAllTasksHint.
  ///
  /// In en, this message translates to:
  /// **'Every open task in ZT Tasks, except the ones you switch off.'**
  String get plannerAllTasksHint;

  /// No description provided for @plannerOnlySwitchedOn.
  ///
  /// In en, this message translates to:
  /// **'Only tasks I switch on'**
  String get plannerOnlySwitchedOn;

  /// No description provided for @plannerOnlySwitchedOnHint.
  ///
  /// In en, this message translates to:
  /// **'Nothing is planned until you switch a task on.'**
  String get plannerOnlySwitchedOnHint;

  /// No description provided for @plannerUsualLength.
  ///
  /// In en, this message translates to:
  /// **'Usual task length'**
  String get plannerUsualLength;

  /// No description provided for @plannerShortestBlock.
  ///
  /// In en, this message translates to:
  /// **'Shortest block'**
  String get plannerShortestBlock;

  /// No description provided for @plannerLongestBlock.
  ///
  /// In en, this message translates to:
  /// **'Longest block'**
  String get plannerLongestBlock;

  /// No description provided for @plannerBreakAfterMeetings.
  ///
  /// In en, this message translates to:
  /// **'Break after meetings'**
  String get plannerBreakAfterMeetings;

  /// No description provided for @plannerNoBreak.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get plannerNoBreak;

  /// No description provided for @plannerMostPerDay.
  ///
  /// In en, this message translates to:
  /// **'Most planned time per day'**
  String get plannerMostPerDay;

  /// No description provided for @plannerBusyCalendars.
  ///
  /// In en, this message translates to:
  /// **'Calendars that count as busy'**
  String get plannerBusyCalendars;

  /// No description provided for @plannerNoBusyCalendars.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get plannerNoBusyCalendars;

  /// No description provided for @plannerPassedCountAsDone.
  ///
  /// In en, this message translates to:
  /// **'Blocks that pass count as done'**
  String get plannerPassedCountAsDone;

  /// No description provided for @plannerPassedCountAsDoneOn.
  ///
  /// In en, this message translates to:
  /// **'A block whose time has passed is marked done.'**
  String get plannerPassedCountAsDoneOn;

  /// No description provided for @plannerPassedCountAsDoneOff.
  ///
  /// In en, this message translates to:
  /// **'A block that passed waits for the rest of the day, then its time is planned again.'**
  String get plannerPassedCountAsDoneOff;

  /// No description provided for @plannerRemindAtStart.
  ///
  /// In en, this message translates to:
  /// **'Notify me when a block starts'**
  String get plannerRemindAtStart;

  /// No description provided for @plannerTidyUp.
  ///
  /// In en, this message translates to:
  /// **'Tidy up my week'**
  String get plannerTidyUp;

  /// No description provided for @plannerTidyUpHint.
  ///
  /// In en, this message translates to:
  /// **'Plans every block afresh, as early as it fits.'**
  String get plannerTidyUpHint;

  /// No description provided for @plannerTidiedUp.
  ///
  /// In en, this message translates to:
  /// **'Planning your week again'**
  String get plannerTidiedUp;

  /// No description provided for @plannerTurnOff.
  ///
  /// In en, this message translates to:
  /// **'Turn off the Planner'**
  String get plannerTurnOff;

  /// No description provided for @plannerTurnOffTitle.
  ///
  /// In en, this message translates to:
  /// **'Turn off the Planner?'**
  String get plannerTurnOffTitle;

  /// No description provided for @plannerTurnOffBody.
  ///
  /// In en, this message translates to:
  /// **'Planned blocks that aren\'t done are removed from your calendar. Your tasks stay as they are in ZT Tasks, and your Planner settings are kept.'**
  String get plannerTurnOffBody;

  /// No description provided for @plannerTaskLength.
  ///
  /// In en, this message translates to:
  /// **'Length'**
  String get plannerTaskLength;

  /// No description provided for @plannerLengthGuess.
  ///
  /// In en, this message translates to:
  /// **'{length} (guess)'**
  String plannerLengthGuess(String length);

  /// No description provided for @plannerPlanIn.
  ///
  /// In en, this message translates to:
  /// **'Plan it in'**
  String get plannerPlanIn;

  /// No description provided for @plannerNothingPlanned.
  ///
  /// In en, this message translates to:
  /// **'Nothing is planned in the next 7 days.'**
  String get plannerNothingPlanned;

  /// No description provided for @plannerPlannedTotal.
  ///
  /// In en, this message translates to:
  /// **'{amount} planned'**
  String plannerPlannedTotal(String amount);

  /// No description provided for @plannerDailyLimit.
  ///
  /// In en, this message translates to:
  /// **'At most {amount} a day'**
  String plannerDailyLimit(String amount);

  /// No description provided for @plannerDoneOf.
  ///
  /// In en, this message translates to:
  /// **'{amount} done'**
  String plannerDoneOf(String amount);

  /// No description provided for @plannerNotPlannedYet.
  ///
  /// In en, this message translates to:
  /// **'not planned yet'**
  String get plannerNotPlannedYet;

  /// No description provided for @plannerNextBlock.
  ///
  /// In en, this message translates to:
  /// **'next: {when}'**
  String plannerNextBlock(String when);

  /// No description provided for @plannerHoursHint.
  ///
  /// In en, this message translates to:
  /// **'The Planner only places blocks inside these hours.'**
  String get plannerHoursHint;

  /// No description provided for @plannerBusyCalendarsHint.
  ///
  /// In en, this message translates to:
  /// **'Events in these calendars keep the Planner away. Untick a calendar whose events you can work through.'**
  String get plannerBusyCalendarsHint;

  /// No description provided for @plannerHiddenCalendar.
  ///
  /// In en, this message translates to:
  /// **'Hidden calendars don\'t count'**
  String get plannerHiddenCalendar;

  /// No description provided for @plannerAllDayBusy.
  ///
  /// In en, this message translates to:
  /// **'All-day events count as busy'**
  String get plannerAllDayBusy;

  /// No description provided for @plannerAllDayBusyHint.
  ///
  /// In en, this message translates to:
  /// **'Nothing is planned on a day with an all-day event, such as a holiday.'**
  String get plannerAllDayBusyHint;

  /// No description provided for @plannerBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get plannerBack;

  /// No description provided for @plannerNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get plannerNext;

  /// No description provided for @plannerTurnOn.
  ///
  /// In en, this message translates to:
  /// **'Turn on the Planner'**
  String get plannerTurnOn;

  /// No description provided for @plannerStepHours.
  ///
  /// In en, this message translates to:
  /// **'Your hours'**
  String get plannerStepHours;

  /// No description provided for @plannerStepHoursBody.
  ///
  /// In en, this message translates to:
  /// **'When may the Planner place tasks? Work tasks go into work hours and personal tasks into personal hours.'**
  String get plannerStepHoursBody;

  /// No description provided for @plannerStepTasks.
  ///
  /// In en, this message translates to:
  /// **'Which tasks'**
  String get plannerStepTasks;

  /// No description provided for @plannerStepTasksBody.
  ///
  /// In en, this message translates to:
  /// **'Choose what the Planner plans. You can change this later.'**
  String get plannerStepTasksBody;

  /// No description provided for @plannerPickTasks.
  ///
  /// In en, this message translates to:
  /// **'Tasks to plan now'**
  String get plannerPickTasks;

  /// No description provided for @plannerStepDefaults.
  ///
  /// In en, this message translates to:
  /// **'Defaults'**
  String get plannerStepDefaults;

  /// No description provided for @plannerStepDefaultsBody.
  ///
  /// In en, this message translates to:
  /// **'Used for tasks that don\'t say otherwise. You can set a length for each task.'**
  String get plannerStepDefaultsBody;

  /// No description provided for @plannerStepPreview.
  ///
  /// In en, this message translates to:
  /// **'Your plan'**
  String get plannerStepPreview;

  /// No description provided for @plannerStepPreviewBody.
  ///
  /// In en, this message translates to:
  /// **'This is what the Planner would add to your calendar. Nothing is saved until you turn it on.'**
  String get plannerStepPreviewBody;

  /// No description provided for @plannerPreviewNoTasks.
  ///
  /// In en, this message translates to:
  /// **'There is nothing to plan yet. After you turn the Planner on, switch on the tasks you want planned.'**
  String get plannerPreviewNoTasks;

  /// No description provided for @plannerPreviewNoRoom.
  ///
  /// In en, this message translates to:
  /// **'No free time was found in your hours in the next 4 weeks.'**
  String get plannerPreviewNoRoom;

  /// No description provided for @plannerNeedMoreTime.
  ///
  /// In en, this message translates to:
  /// **'Need more time'**
  String get plannerNeedMoreTime;

  /// No description provided for @plannerDidNotDoIt.
  ///
  /// In en, this message translates to:
  /// **'Didn\'t do it'**
  String get plannerDidNotDoIt;

  /// No description provided for @plannerDidNotDoItHint.
  ///
  /// In en, this message translates to:
  /// **'Its time is planned again.'**
  String get plannerDidNotDoItHint;

  /// No description provided for @plannerFinishedBlock.
  ///
  /// In en, this message translates to:
  /// **'Finished this block?'**
  String get plannerFinishedBlock;

  /// No description provided for @plannerFinishedTitle.
  ///
  /// In en, this message translates to:
  /// **'Finished {title}?'**
  String plannerFinishedTitle(String title);

  /// No description provided for @plannerMovedAndLocked.
  ///
  /// In en, this message translates to:
  /// **'Moved to {when} and locked there'**
  String plannerMovedAndLocked(String when);

  /// No description provided for @plannerMarkedDone.
  ///
  /// In en, this message translates to:
  /// **'Marked as done'**
  String get plannerMarkedDone;

  /// No description provided for @plannerMarkedNotDone.
  ///
  /// In en, this message translates to:
  /// **'Marked as not done'**
  String get plannerMarkedNotDone;

  /// No description provided for @plannerHowMuchMore.
  ///
  /// In en, this message translates to:
  /// **'How much more time?'**
  String get plannerHowMuchMore;

  /// No description provided for @plannerAddedTime.
  ///
  /// In en, this message translates to:
  /// **'Added to the task: {amount}'**
  String plannerAddedTime(String amount);

  /// No description provided for @plannerLaterToday.
  ///
  /// In en, this message translates to:
  /// **'Later today'**
  String get plannerLaterToday;

  /// No description provided for @plannerLaterThatDay.
  ///
  /// In en, this message translates to:
  /// **'Later that day'**
  String get plannerLaterThatDay;

  /// No description provided for @plannerTheDayAfter.
  ///
  /// In en, this message translates to:
  /// **'The day after'**
  String get plannerTheDayAfter;

  /// No description provided for @plannerAWeekLater.
  ///
  /// In en, this message translates to:
  /// **'A week later'**
  String get plannerAWeekLater;

  /// No description provided for @plannerNotNowUntil.
  ///
  /// In en, this message translates to:
  /// **'When should it be planned again?'**
  String get plannerNotNowUntil;

  /// No description provided for @plannerPlannedAgainFrom.
  ///
  /// In en, this message translates to:
  /// **'Not planned before: {when}'**
  String plannerPlannedAgainFrom(String when);

  /// No description provided for @plannerPlannedAgain.
  ///
  /// In en, this message translates to:
  /// **'Its time will be planned again'**
  String get plannerPlannedAgain;

  /// No description provided for @plannerBlockOverlaps.
  ///
  /// In en, this message translates to:
  /// **'This block overlaps an event.'**
  String get plannerBlockOverlaps;

  /// No description provided for @plannerNotDoneAfterAll.
  ///
  /// In en, this message translates to:
  /// **'Not done after all'**
  String get plannerNotDoneAfterAll;

  /// No description provided for @plannerAlreadyDone.
  ///
  /// In en, this message translates to:
  /// **'Already done'**
  String get plannerAlreadyDone;

  /// No description provided for @plannerAlreadyDoneHint.
  ///
  /// In en, this message translates to:
  /// **'Frees the time that was planned for it.'**
  String get plannerAlreadyDoneHint;

  /// No description provided for @plannerNotNow.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get plannerNotNow;

  /// No description provided for @plannerUnlock.
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get plannerUnlock;

  /// No description provided for @plannerLockHere.
  ///
  /// In en, this message translates to:
  /// **'Lock here'**
  String get plannerLockHere;

  /// No description provided for @plannerLockHereHint.
  ///
  /// In en, this message translates to:
  /// **'The Planner will not move it.'**
  String get plannerLockHereHint;

  /// No description provided for @plannerUnlocked.
  ///
  /// In en, this message translates to:
  /// **'Unlocked. The Planner may move it again.'**
  String get plannerUnlocked;

  /// No description provided for @plannerLocked.
  ///
  /// In en, this message translates to:
  /// **'Locked at this time'**
  String get plannerLocked;

  /// No description provided for @plannerTasksAtRisk.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 task is at risk} other{{count} tasks are at risk}}'**
  String plannerTasksAtRisk(int count);

  /// No description provided for @plannerAtRiskTitle.
  ///
  /// In en, this message translates to:
  /// **'Tasks at risk'**
  String get plannerAtRiskTitle;

  /// No description provided for @plannerAtRiskBody.
  ///
  /// In en, this message translates to:
  /// **'These tasks don\'t fit before their due date. Tap one to change its length or its due date, or make room in your calendar.'**
  String get plannerAtRiskBody;

  /// No description provided for @plannerAtRiskNone.
  ///
  /// In en, this message translates to:
  /// **'Every task fits now.'**
  String get plannerAtRiskNone;

  /// No description provided for @plannerOpenPlanner.
  ///
  /// In en, this message translates to:
  /// **'Open the Planner'**
  String get plannerOpenPlanner;

  /// No description provided for @plannerFixLength.
  ///
  /// In en, this message translates to:
  /// **'Change the length'**
  String get plannerFixLength;

  /// No description provided for @plannerFixLengthNow.
  ///
  /// In en, this message translates to:
  /// **'Now {amount}'**
  String plannerFixLengthNow(String amount);

  /// No description provided for @plannerFixDue.
  ///
  /// In en, this message translates to:
  /// **'Move the due date'**
  String get plannerFixDue;

  /// No description provided for @plannerFixStop.
  ///
  /// In en, this message translates to:
  /// **'Stop planning this task'**
  String get plannerFixStop;

  /// No description provided for @plannerAskAtEnd.
  ///
  /// In en, this message translates to:
  /// **'Ask when a block ends'**
  String get plannerAskAtEnd;

  /// No description provided for @plannerAskAtEndHint.
  ///
  /// In en, this message translates to:
  /// **'A notification asks whether you finished. Its buttons work while Calendar is locked.'**
  String get plannerAskAtEndHint;

  /// No description provided for @markAsDone.
  ///
  /// In en, this message translates to:
  /// **'Mark as done'**
  String get markAsDone;

  /// No description provided for @markAsNotDone.
  ///
  /// In en, this message translates to:
  /// **'Mark as not done'**
  String get markAsNotDone;

  /// No description provided for @plannerDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get plannerDone;

  /// No description provided for @plannerHabits.
  ///
  /// In en, this message translates to:
  /// **'Habits'**
  String get plannerHabits;

  /// No description provided for @plannerNoHabits.
  ///
  /// In en, this message translates to:
  /// **'Keep time for lunch, exercise or anything you do regularly.'**
  String get plannerNoHabits;

  /// No description provided for @plannerAddHabit.
  ///
  /// In en, this message translates to:
  /// **'Add a habit'**
  String get plannerAddHabit;

  /// No description provided for @plannerEditHabit.
  ///
  /// In en, this message translates to:
  /// **'Edit habit'**
  String get plannerEditHabit;

  /// No description provided for @plannerHabitLunch.
  ///
  /// In en, this message translates to:
  /// **'Lunch'**
  String get plannerHabitLunch;

  /// No description provided for @plannerHabitExercise.
  ///
  /// In en, this message translates to:
  /// **'Exercise'**
  String get plannerHabitExercise;

  /// No description provided for @plannerHabitOther.
  ///
  /// In en, this message translates to:
  /// **'Something else'**
  String get plannerHabitOther;

  /// No description provided for @plannerHabitUntitled.
  ///
  /// In en, this message translates to:
  /// **'Habit'**
  String get plannerHabitUntitled;

  /// No description provided for @plannerHabitName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get plannerHabitName;

  /// No description provided for @plannerHabitNameHint.
  ///
  /// In en, this message translates to:
  /// **'For example: Reading'**
  String get plannerHabitNameHint;

  /// No description provided for @plannerHabitDays.
  ///
  /// In en, this message translates to:
  /// **'Days'**
  String get plannerHabitDays;

  /// No description provided for @plannerHabitLength.
  ///
  /// In en, this message translates to:
  /// **'Length'**
  String get plannerHabitLength;

  /// No description provided for @plannerHabitIdeal.
  ///
  /// In en, this message translates to:
  /// **'Best time to start'**
  String get plannerHabitIdeal;

  /// No description provided for @plannerHabitWindow.
  ///
  /// In en, this message translates to:
  /// **'Only between'**
  String get plannerHabitWindow;

  /// No description provided for @plannerHabitWindowTooShort.
  ///
  /// In en, this message translates to:
  /// **'Too short for the habit\'s length.'**
  String get plannerHabitWindowTooShort;

  /// No description provided for @plannerHabitBetween.
  ///
  /// In en, this message translates to:
  /// **'{from} to {to}'**
  String plannerHabitBetween(String from, String to);

  /// No description provided for @plannerHabitFrom.
  ///
  /// In en, this message translates to:
  /// **'From'**
  String get plannerHabitFrom;

  /// No description provided for @plannerHabitTo.
  ///
  /// In en, this message translates to:
  /// **'To'**
  String get plannerHabitTo;

  /// No description provided for @plannerHabitNoRoom.
  ///
  /// In en, this message translates to:
  /// **'When there\'s no room'**
  String get plannerHabitNoRoom;

  /// No description provided for @plannerHabitSkipDay.
  ///
  /// In en, this message translates to:
  /// **'Skip that day'**
  String get plannerHabitSkipDay;

  /// No description provided for @plannerHabitShortenTo.
  ///
  /// In en, this message translates to:
  /// **'Shorten it, down to {length}'**
  String plannerHabitShortenTo(String length);

  /// No description provided for @plannerAnyTime.
  ///
  /// In en, this message translates to:
  /// **'Any time'**
  String get plannerAnyTime;

  /// No description provided for @plannerHabitPaused.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get plannerHabitPaused;

  /// No description provided for @plannerHabitPausedHint.
  ///
  /// In en, this message translates to:
  /// **'Kept, but not planned until you switch this off.'**
  String get plannerHabitPausedHint;

  /// No description provided for @plannerHabitPausedShort.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get plannerHabitPausedShort;

  /// No description provided for @plannerDeleteHabitTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this habit?'**
  String get plannerDeleteHabitTitle;

  /// No description provided for @plannerDeleteHabitBody.
  ///
  /// In en, this message translates to:
  /// **'Its coming times are removed from the calendar. Past ones stay.'**
  String get plannerDeleteHabitBody;

  /// No description provided for @plannerEveryDay.
  ///
  /// In en, this message translates to:
  /// **'Every day'**
  String get plannerEveryDay;

  /// No description provided for @plannerAround.
  ///
  /// In en, this message translates to:
  /// **'around {time}'**
  String plannerAround(String time);

  /// No description provided for @plannerSkipToday.
  ///
  /// In en, this message translates to:
  /// **'Skip today'**
  String get plannerSkipToday;

  /// No description provided for @plannerSkipTodayHint.
  ///
  /// In en, this message translates to:
  /// **'Frees the time. It isn\'t planned again today.'**
  String get plannerSkipTodayHint;

  /// No description provided for @plannerHabitSkipped.
  ///
  /// In en, this message translates to:
  /// **'Skipped'**
  String get plannerHabitSkipped;

  /// No description provided for @plannerHabitSkippedToday.
  ///
  /// In en, this message translates to:
  /// **'Skipped'**
  String get plannerHabitSkippedToday;

  /// No description provided for @plannerHabitKeptAfterAll.
  ///
  /// In en, this message translates to:
  /// **'Did it after all'**
  String get plannerHabitKeptAfterAll;

  /// No description provided for @plannerHabitSkippedAfterAll.
  ///
  /// In en, this message translates to:
  /// **'Skipped it after all'**
  String get plannerHabitSkippedAfterAll;

  /// No description provided for @plannerFocusGoal.
  ///
  /// In en, this message translates to:
  /// **'Focus time each week'**
  String get plannerFocusGoal;

  /// No description provided for @plannerFocusOff.
  ///
  /// In en, this message translates to:
  /// **'Off. Keeps time free of meetings for deep work.'**
  String get plannerFocusOff;

  /// No description provided for @plannerFocusOffShort.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get plannerFocusOffShort;

  /// No description provided for @plannerFocusPerWeek.
  ///
  /// In en, this message translates to:
  /// **'{amount} a week, in work hours'**
  String plannerFocusPerWeek(String amount);

  /// No description provided for @plannerFocusBlockTitle.
  ///
  /// In en, this message translates to:
  /// **'Focus time'**
  String get plannerFocusBlockTitle;

  /// No description provided for @plannerWeekFocus.
  ///
  /// In en, this message translates to:
  /// **'Focus time: {planned} of {goal}'**
  String plannerWeekFocus(String planned, String goal);

  /// No description provided for @plannerWeekHabits.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 habit time planned} other{{count} habit times planned}}'**
  String plannerWeekHabits(int count);

  /// No description provided for @plannerLastWeekDone.
  ///
  /// In en, this message translates to:
  /// **'Last 7 days: {amount} of tasks done'**
  String plannerLastWeekDone(String amount);

  /// No description provided for @plannerLastWeekHabits.
  ///
  /// In en, this message translates to:
  /// **'habits kept {kept} of {total}'**
  String plannerLastWeekHabits(int kept, int total);

  /// No description provided for @findTimeForTask.
  ///
  /// In en, this message translates to:
  /// **'Find a time for a task'**
  String get findTimeForTask;

  /// No description provided for @findTimePickTask.
  ///
  /// In en, this message translates to:
  /// **'Which task?'**
  String get findTimePickTask;

  /// No description provided for @findTimeNoTasks.
  ///
  /// In en, this message translates to:
  /// **'No open tasks in ZT Tasks. Add a task there, then come back.'**
  String get findTimeNoTasks;

  /// No description provided for @findTimeDue.
  ///
  /// In en, this message translates to:
  /// **'Due {day}'**
  String findTimeDue(String day);

  /// No description provided for @findTimeFreeTimes.
  ///
  /// In en, this message translates to:
  /// **'Free times'**
  String get findTimeFreeTimes;

  /// No description provided for @findTimeNone.
  ///
  /// In en, this message translates to:
  /// **'No free time in the next two weeks. Try a shorter length or other hours.'**
  String get findTimeNone;

  /// No description provided for @findTimeAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get findTimeAdd;

  /// No description provided for @findTimeHint.
  ///
  /// In en, this message translates to:
  /// **'The task is added as an event linked to it. It stays where you put it.'**
  String get findTimeHint;

  /// No description provided for @findTimeAdded.
  ///
  /// In en, this message translates to:
  /// **'Added to your calendar: {when}'**
  String findTimeAdded(String when);

  /// No description provided for @plannerPlusTitle.
  ///
  /// In en, this message translates to:
  /// **'The automatic Planner is part of Plus'**
  String get plannerPlusTitle;

  /// No description provided for @plannerPlusBody.
  ///
  /// In en, this message translates to:
  /// **'With Plus, Calendar plans your tasks, habits and focus time and moves them when your day changes. Plus isn\'t on sale yet. On the free plan, Find a time places one task at a time.'**
  String get plannerPlusBody;

  /// No description provided for @plannerPausedTitle.
  ///
  /// In en, this message translates to:
  /// **'The Planner is paused'**
  String get plannerPausedTitle;

  /// No description provided for @plannerPausedBody.
  ///
  /// In en, this message translates to:
  /// **'Your plan no longer includes the Planner (it is part of Plus). Your blocks stay where they are, but nothing moves them now.'**
  String get plannerPausedBody;

  /// No description provided for @plannerCheckPlan.
  ///
  /// In en, this message translates to:
  /// **'Check my plan again'**
  String get plannerCheckPlan;
}

class _AppL10nDelegate extends LocalizationsDelegate<AppL10n> {
  const _AppL10nDelegate();

  @override
  Future<AppL10n> load(Locale locale) {
    return SynchronousFuture<AppL10n>(lookupAppL10n(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'he'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppL10nDelegate old) => false;
}

AppL10n lookupAppL10n(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppL10nEn();
    case 'he':
      return AppL10nHe();
  }

  throw FlutterError(
    'AppL10n.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
