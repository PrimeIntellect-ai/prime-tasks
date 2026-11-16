Parser not finding all strings
Not all translateService.instant translations are extracted

package.json
```
{
	"name": "translations",
	"version": "1.0.0",
	"description": "Translations for the interface",
	"scripts": {
		"scan-translations": "ngx-translate-extract --input ./api_translations ./interface_instance/src --format pot --output ./found-translations.pot",
		"test": "echo \"Error: no test specified\" && exit 1"
	},
	"author": "",
	"license": "ISC",
	"devDependencies": {
		"@angular/compiler": "17.3.11",
		"@types/node": "20.14.9",
		"@vendure/ngx-translate-extract": "9.2.0",
		"braces": "3.0.3",
		"ts-node": "10.9.2",
		"typescript": "5.5.3"
	}
}
```

media.service.ts
```
import {HttpClient} from '@angular/common/http';
import {Injectable} from '@angular/core';
import {TranslateService} from '@ngx-translate/core';
import {ApprovalStatusEnum} from 'src/app/admin/data/backend/media/approval-status.enum';
import {ApprovalStatusInterface} from 'src/app/admin/data/backend/media/approval-status.interface';
import {MethodEnum} from 'src/app/admin/data/backend/media/method.enum';
import {MethodInterface} from 'src/app/admin/data/backend/media/method.interface';
import {TypeEnum as BadgeTypeEnum} from 'src/app/core/components/badge/type.enum';
import {MediaService as CoreMediaService} from 'src/app/core/data/backend/media/media.service';
import {CacheService} from 'src/app/core/data/cache/cache.service';

@Injectable({providedIn: 'root'})
export class MediaService extends CoreMediaService {
	constructor(
		protected cacheService: CacheService,
		protected httpClient: HttpClient,
		translateService: TranslateService
	) {
		super(translateService);
	}

	public getApprovalStatuses(): Record<ApprovalStatusEnum, ApprovalStatusInterface> {
		return {
			[ApprovalStatusEnum.APPROVED]: <ApprovalStatusInterface>{
				badgeType: BadgeTypeEnum.SUCCESS,
				value: ApprovalStatusEnum.APPROVED,
				label: this.translateService.instant('media_approval_status_approved')
			},
			[ApprovalStatusEnum.DISAPPROVED]: <ApprovalStatusInterface>{
				badgeType: BadgeTypeEnum.DANGER,
				value: ApprovalStatusEnum.DISAPPROVED,
				label: this.translateService.instant('media_approval_status_disapproved')
			},
			[ApprovalStatusEnum.OPEN]: <ApprovalStatusInterface>{
				badgeType: BadgeTypeEnum.WARNING,
				value: ApprovalStatusEnum.OPEN,
				label: this.translateService.instant('media_approval_status_open')
			},
			[ApprovalStatusEnum.PENDING]: <ApprovalStatusInterface>{
				badgeType: BadgeTypeEnum.WARNING,
				value: ApprovalStatusEnum.PENDING,
				label: this.translateService.instant('media_approval_status_pending')
			},
		};
	}

	public getVerificationMethods(): Record<MethodEnum, MethodInterface> {
		return {
			[MethodEnum.ADMIN]: <MethodInterface>{
				value: MethodEnum.ADMIN,
				label: this.translateService.instant('media_verification_method_admin'),
			},
			[MethodEnum.DNS]: <MethodInterface>{
				value: MethodEnum.DNS,
				label: this.translateService.instant('media_verification_method_dns'),
			},
			[MethodEnum.METATAG]: <MethodInterface>{
				value: MethodEnum.METATAG,
				label: this.translateService.instant('media_verification_method_metatag'),
			},
			[MethodEnum.PAGE]: <MethodInterface>{
				value: MethodEnum.PAGE,
				label: this.translateService.instant('media_verification_method_page'),
			},
			[MethodEnum.NONE]: <MethodInterface>{
				value: MethodEnum.NONE,
				label: this.translateService.instant('media_verification_method_none'),
			},
		};
	}
}
```

core/media.service.ts
```
import {Injectable} from '@angular/core';
import {TranslateService} from '@ngx-translate/core';
import {TypeEnum as BadgeTypeEnum} from 'src/app/core/components/badge/type.enum';
import {TypeGroupEnum} from 'src/app/core/data/backend/media/type-group.enum';
import {TypeGroupInterface} from 'src/app/core/data/backend/media/type-group.interface';

@Injectable()
export class MediaService {
	constructor(
		protected translateService: TranslateService
	) {}

	public getMediaTypeGroups(): Record<TypeGroupEnum, TypeGroupInterface> {
		return <Record<TypeGroupEnum, TypeGroupInterface>>{
			[TypeGroupEnum.GROUPA]: <TypeGroupInterface>{
				badgeType: BadgeTypeEnum.CYAN,
				id: TypeGroupEnum.GROUP_A,
				label: this.translateService.instant('media_type_group_a')
			},
			[TypeGroupEnum.GROUPB]: <TypeGroupInterface>{
				badgeType: BadgeTypeEnum.LIGHT_BROWN,
				id: TypeGroupEnum.GROUP_B,
				label: this.translateService.instant('media_type_group_b')
			},
		};
	}
}
```

command
```
npx ngx-translate-extract --input interface_instance/src/app/admin/data/backend/media/media.service.ts --format pot --output test.pot
```

result:
```
Enabled parsers:
- PipeParser
- DirectiveParser
- ServiceParser
- MarkerParser

Enabled post processors:
(none)

Compiler:
- PoCompiler

Extracting:
- /home/samantha/vhosts/translations/interface_instance/src/app/admin/data/backend/media/media.service.ts

Found 0 strings.

Saving:
- /home/samantha/vhosts/translations/test.txt [CREATED]

Done.
```
