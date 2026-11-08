Name-spacing Error in related class imports in factory when using name-spaced model

- Laravel Version: 8.31.0
- PHP Version: 7.4.14
- Blueprint Version: dev-master
- Platform: Mac | Windows | Linux

### Issue:


### draft.yaml:
```yaml
models:

  QuestionFormat:
    format: string

  QuestionType:
    description: string


  Appointment/AppointmentType:
    name: string
    slug: string
    version: integer default:1
    description: text


  Appointment/Reservation:
    first_name: string
    last_name: string
    email: string nullable
    phone: string nullable
    dob: date nullable
    phin: integer nullable
    mb_health_number: integer nullable
    confirmed_at: timestamp nullable

# Appointment is getting to large, thought I'd begin name-spacing it to block development off a bit.
# as a test I tried only this model
  Appointment/ScreeningQuestion:
    appointment_type_id: id foreign
    question_format_id: id foreign
    question_type_id: id foreign
    order: integer default:1
    required: bool default:true
    placeholder: string nullable
    question: string
    hint: string nullable

  Appointment/ScreenQuestionOptions:
    appointment_question_id: id foreign
    key: string
    value: string
    order: integer default:1
```

It actually works quite well it looses track of the name space of the other components. It will create the what appears to be the correct files, however  the namespace will always be the current namespace and not the actual namespace.

```
Directory list
Created:
- database/factories/QuestionFormatFactory.php
- database/factories/QuestionTypeFactory.php
- database/factories/Appointment/AppointmentTypeFactory.php
- database/factories/Appointment/ReservationFactory.php
- database/factories/Appointment/ScreeningQuestionFactory.php
- database/factories/Appointment/ScreeningQuestionOptionsFactory.php
- database/migrations/2021_03_09_173506_create_question_formats_table.php
- database/migrations/2021_03_09_173507_create_question_types_table.php
- database/migrations/2021_03_09_173508_create_appointment_types_table.php
- database/migrations/2021_03_09_173509_create_reservations_table.php
- database/migrations/2021_03_09_173510_create_screening_questions_table.php
- database/migrations/2021_03_09_173511_create_screening_question_options_table.php
- app/Models/QuestionFormat.php
- app/Models/QuestionType.php
- app/Models/Appointment/AppointmentType.php
- app/Models/Appointment/Reservation.php
- app/Models/Appointment/ScreeningQuestion.php
- app/Models/Appointment/ScreeningQuestionOptions.php
```

This file illustrates the issue:
notice the path to the QuestionFormat and QuestionType class that have been left out of the Appointment namespace.
The same thing happens in the model factories.

```php
<?php

namespace App\Models\Appointment;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

/**
 * @property int $id
 * @property int $appointment_type_id
 * @property int $question_format_id
 * @property int $question_type_id
 * @property int $order
 * @property string $required
 * @property string $placeholder
 * @property string $question
 * @property string $hint
 * @property \Carbon\Carbon $created_at
 * @property \Carbon\Carbon $updated_at
 */
class ScreeningQuestion extends Model
{
    use HasFactory;

    /**
     * The attributes that are mass assignable.
     *
     * @var array
     */
    protected $fillable = [
        'appointment_type_id',
        'question_format_id',
        'question_type_id',
        'order',
        'required',
        'placeholder',
        'question',
        'hint',
    ];

    /**
     * The attributes that should be cast to native types.
     *
     * @var array
     */
    protected $casts = [
        'id' => 'integer',
        'appointment_type_id' => 'integer',
        'question_format_id' => 'integer',
        'question_type_id' => 'integer',
    ];


    /**
     * @return \Illuminate\Database\Eloquent\Relations\BelongsTo
     */
    public function appointmentType()
    {
        return $this->belongsTo(\App\Models\Appointment\AppointmentType::class);
    }

    /**
     * @return \Illuminate\Database\Eloquent\Relations\BelongsTo
     */
    public function questionFormat()
    {
        return $this->belongsTo(\App\Models\Appointment\QuestionFormat::class);
    }

    /**
     * @return \Illuminate\Database\Eloquent\Relations\BelongsTo
     */
    public function questionType()
    {
        return $this->belongsTo(\App\Models\Appointment\QuestionType::class);
    }
}
```

Factory
```php
<?php

namespace Database\Factories;

use Illuminate\Database\Eloquent\Factories\Factory;
use Illuminate\Support\Str;
use App\Models\Appointment\AppointmentType;
use App\Models\Appointment\QuestionFormat;
use App\Models\Appointment\QuestionType;
use App\Models\Appointment\ScreeningQuestion;

class ScreeningQuestionFactory extends Factory
{
    /**
     * The name of the factory's corresponding model.
     *
     * @var string
     */
    protected $model = ScreeningQuestion::class;

    /**
     * Define the model's default state.
     *
     * @return array
     */
    public function definition()
    {
        return [
            'appointment_type_id' => AppointmentType::factory(),
            'question_format_id' => QuestionFormat::factory(),
            'question_type_id' => QuestionType::factory(),
            'order' => $this->faker->numberBetween(-10000, 10000),
            'required' => $this->faker->word,
            'placeholder' => $this->faker->word,
            'question' => $this->faker->word,
            'hint' => $this->faker->word,
        ];
    }
}

```
