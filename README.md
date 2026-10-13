# MiComunidad

*Community management application by Fabrizio Venegas*

MiComunidad is a mobile application for organizing community information and supporting resident participation.

## Introduction and Motivation

Through my experience in community volunteering, including taking on a coordination role, I became interested in how information about local needs, projects, and agreements is organized and maintained over time. When that information is spread across messages, documents, and meetings, it can be difficult to consult previous decisions, identify priorities, and follow project progress.

This motivated me to develop MiComunidad, a mobile application designed to bring community information into one place and support communication, planning, and follow-up. The application provides different levels of access for residents and administrators, allowing residents to report local issues and administrators to review them alongside ongoing projects and activities.

## My Role and Contributions

I conceived MiComunidad and wrote its initial project proposal, translating community needs into detailed functional requirements. I designed the application’s screen structure, navigation, user roles, and access boundaries, specifying what information each section would display and which actions residents and administrators could perform.

I planned the main workflows for reporting local issues, reviewing submissions, tracking project progress, organizing activities, and managing access requests. As the project developed, I refined these requirements, reviewed the interface, and checked the application’s behavior in emulators and Android builds. I also prioritized separating public and private configurations to reduce the exposure of community information.

## Main Features

- **Access and member management.** Residents request access; administrators review applications and manage membership. Navigation depends on the approved user role.
- **Reports and moderation.** Residents submit issues with descriptions, categories, priorities and optional photos. Administrators review them before operational tracking; completed reports appear in History.
- **Projects and archives.** Projects show progress and supporting content. Administrators manage active projects, archive them and restore them when needed.
- **Interactive map.** Geographic reference points provide context. The public configuration uses fictional coordinates instead of the real community location.
- **Community agenda.** Authorized users consult internal meetings and activities; administrators manage the schedule and associated information.

## Screenshots

These screenshots show the app’s interface populated with fictional demonstration data, not actual community activity. The map uses an unrelated public basemap with an invented boundary and markers; it does not show the community’s location.

### 1. Access and member management

<p align="center">
  <img src="docs/screenshots/access-requests.png" width="300" alt="Access requests with pending, approved, rejected and withdrawn-access statuses" />
  &nbsp;&nbsp;
  <img src="docs/screenshots/members.png" width="300" alt="Member list showing fictional residents and administrators" />
</p>

<p align="center"><em>Access requests · Members and roles</em></p>

### 2. Reports and moderation

<p align="center">
  <img src="docs/screenshots/report-moderation.png" width="300" alt="Administrator review panel with pending reports and approval and rejection controls" />
  &nbsp;&nbsp;
  <img src="docs/screenshots/report-tracking.png" width="300" alt="Report cards showing operational statuses, priorities and a rejection reason" />
</p>

<p align="center"><em>Moderation · Report tracking</em></p>

### 3. Projects and archives

<p align="center">
  <img src="docs/screenshots/projects.png" width="300" alt="Community projects with status filters and progress percentages" />
  &nbsp;&nbsp;
  <img src="docs/screenshots/archived-projects.png" width="300" alt="Archived projects with information, restoration and permanent deletion options" />
</p>

<p align="center"><em>Active projects · Archived projects</em></p>

### 4. Interactive map

<p align="center">
  <img src="docs/screenshots/map.png" width="300" alt="Interactive map with a fictional community boundary, reference points and visible OpenStreetMap attribution" />
</p>

### 5. Community agenda

<p align="center">
  <img src="docs/screenshots/agenda.png" width="300" alt="Community agenda with fictional meetings, activities, dates and locations" />
</p>

## Technical Challenges and Lessons Learned

### Aligning application behavior with Firebase permissions

Residents initially could not see their own pending reports, and Firebase blocked attempts to save report edits. These problems showed that the app and its permissions must work together. I learned that showing a button is not enough: Firebase must also allow the action without giving users access to other people’s information.

### Deleting records and their associated content safely

Deleting a project or report also meant removing its photographs and comments. The process removes this related content first and only deletes the main record once those steps succeed. I learned that deletion must handle errors clearly and allow a safe retry if something goes wrong.

### Preparing a public version while protecting community information

Preparing the project for GitHub meant separating real community names, locations, photographs, and private Firebase settings from the public code. I created separate public and private versions of the app. I learned that excluding a file from GitHub does not guarantee it is excluded from the APK, so both need to be checked before sharing.

## Technologies

- **Flutter and Dart:** The app’s screens, navigation, and how it works.
- **Firebase Authentication:** User sign-in and account authentication.
- **Cloud Firestore:** Stores application information and keeps it updated.
- **Firebase Storage:** Stores photographs and document attachments.
- **Cloud Functions:** Handle tasks such as reviewing access requests and managing members.
- **Firebase Security Rules:** Control who can view or change information and files.
- **OpenStreetMap and OpenTopoMap:** Street and terrain maps, with credit to their creators.
- **flutter_map and latlong2:** Display the interactive map and handle location coordinates.

## Current Project Status

MiComunidad implements the main workflows described above. Using its connected features requires a configured Firebase project with the necessary services and access rules. Without this configuration, the public example builds and starts with a “Firebase not configured” message rather than opening its internal screens.

The public edition uses anonymized examples and keeps real community data and private Firebase configuration separate from the code shared on GitHub.

For build instructions, configuration examples and privacy considerations, see the [setup guide](docs/SETUP.md).
