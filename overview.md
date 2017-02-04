#Send Smart Email
This extension enables sending custom emails during your Build or Release pipeline with parameterized inputs. This extension will make life of a developer a lot easier. You are welcome to request new tools if you can think of a useful new task that does not exist yet. If you are happy with this task, please be so kind to add your (5-star) review on the Marketplace.

##What can you do
* Define one or many recipients, To and CC
* Custom From address
* Paramterized VSO credentials
* Test Plan ID
* Additional HTML Message

##Usage
This task does one simple thing: it sends an email to the address(es) you defined in your definition. You can use it to notify team-members of a
 build which starts, or just ended (note that TFS and VSTS are equipped with build-alerts as well!), but you can defined the contents of the message yourself. IF you use it in a Release-definition it could warn people that a specific environment or server could experience short downtime, etc. It gives the detailed information about the various tests passed/failed with detailed exception message.

##More information
Source can be found here on [Github](https://github.com/deepakkamboj/SendSmartEmail-BuildTask)

Follow my blog for updates [Road to ALM](http://www.deepakkamboj.com)
