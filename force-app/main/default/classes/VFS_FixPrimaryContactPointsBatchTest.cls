/**
 * @description Test unitario para VFS_FixPrimaryContactPointsBatch.
 *              Valida que cuentas sin vías de contacto principales queden con al menos una
 *              marcada como IsPrimary = true, respetando cuentas que ya tienen principal.
 * @author Keystone Advisors - @dev-salesforce
 * @correlative SOL-0269
 */
@isTest
private class VFS_FixPrimaryContactPointsBatchTest {

    @testSetup
    static void setupTestData() {
        // Crear cuentas de prueba
        Account accWithNoPrimary = new Account(
            Name = 'Empresa Prueba Sin Primario SRL'
        );
        Account accWithPrimary = new Account(
            Name = 'Empresa Prueba Con Primario SA'
        );
        insert new List<Account>{ accWithNoPrimary, accWithPrimary };

        // Insertar ContactPointPhone para ambas cuentas
        ContactPointPhone phone1 = new ContactPointPhone(
            ParentId = accWithNoPrimary.Id,
            TelephoneNumber = '8095551001',
            IsPrimary = false
        );
        ContactPointPhone phone2 = new ContactPointPhone(
            ParentId = accWithNoPrimary.Id,
            TelephoneNumber = '8095551002',
            IsPrimary = false
        );
        ContactPointPhone phoneWithPrimary = new ContactPointPhone(
            ParentId = accWithPrimary.Id,
            TelephoneNumber = '8095552001',
            IsPrimary = true
        );
        insert new List<ContactPointPhone>{ phone1, phone2, phoneWithPrimary };

        // Insertar ContactPointEmail
        ContactPointEmail email1 = new ContactPointEmail(
            ParentId = accWithNoPrimary.Id,
            EmailAddress = 'contacto1@empresa.com',
            IsPrimary = false
        );
        ContactPointEmail emailWithPrimary = new ContactPointEmail(
            ParentId = accWithPrimary.Id,
            EmailAddress = 'principal@empresa.com',
            IsPrimary = true
        );
        insert new List<ContactPointEmail>{ email1, emailWithPrimary };

        // Insertar ContactPointAddress
        ContactPointAddress addr1 = new ContactPointAddress(
            ParentId = accWithNoPrimary.Id,
            Name = 'Sucursal Principal',
            City = 'Santo Domingo',
            Country = 'República Dominicana',
            IsPrimary = false
        );
        ContactPointAddress addrWithPrimary = new ContactPointAddress(
            ParentId = accWithPrimary.Id,
            Name = 'Sede Central',
            City = 'Santiago',
            Country = 'República Dominicana',
            IsPrimary = true
        );
        insert new List<ContactPointAddress>{ addr1, addrWithPrimary };
    }

    @isTest
    static void testBatchExecution() {
        Test.startTest();
        VFS_FixPrimaryContactPointsBatch batch = new VFS_FixPrimaryContactPointsBatch();
        Database.executeBatch(batch, 10);
        Test.stopTest();

        // Validar que la cuenta sin primarios ahora tenga al menos 1 IsPrimary = true en cada objeto
        Account accNoPrimary = [SELECT Id FROM Account WHERE Name = 'Empresa Prueba Sin Primario SRL' LIMIT 1];
        
        List<ContactPointPhone> phones = [
            SELECT Id, IsPrimary 
            FROM ContactPointPhone 
            WHERE ParentId = :accNoPrimary.Id AND IsPrimary = true
        ];
        System.assertEquals(1, phones.size(), 'Debe haber exactamente un teléfono marcado como IsPrimary');

        List<ContactPointEmail> emails = [
            SELECT Id, IsPrimary 
            FROM ContactPointEmail 
            WHERE ParentId = :accNoPrimary.Id AND IsPrimary = true
        ];
        System.assertEquals(1, emails.size(), 'Debe haber exactamente un email marcado como IsPrimary');

        List<ContactPointAddress> addrs = [
            SELECT Id, IsPrimary 
            FROM ContactPointAddress 
            WHERE ParentId = :accNoPrimary.Id AND IsPrimary = true
        ];
        System.assertEquals(1, addrs.size(), 'Debe haber exactamente una dirección marcada como IsPrimary');

        // Validar que la cuenta con primarios preexistentes no se haya alterado
        Account accWithPrimary = [SELECT Id FROM Account WHERE Name = 'Empresa Prueba Con Primario SA' LIMIT 1];
        List<ContactPointPhone> origPhones = [
            SELECT Id, IsPrimary 
            FROM ContactPointPhone 
            WHERE ParentId = :accWithPrimary.Id AND IsPrimary = true
        ];
        System.assertEquals(1, origPhones.size(), 'La cuenta con primario previo debe conservar su teléfono intacto');
    }
}
